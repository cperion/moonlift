package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local LJ = T.LalinLuaJIT
local Kernel = T.LalinKernel

local Lower = require("lalin.luajit_lower")(T)
local Emit = require("lalin.luajit_emit")(T)
local Backend = require("lalin.luajit_backend")(T)

local origin = Code.CodeOriginGenerated("test_luajit_lower")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_access = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty)
    return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin)
end

local function inst(id, kind)
    return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin)
end

local function term(id, kind)
    return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin)
end

local xs = param("xs", ptr_i32)
local n = param("n", i32)
local zero = Code.CodeValueId("v:zero")
local one = Code.CodeValueId("v:one")
local i = Code.CodeValueId("v:i")
local acc = Code.CodeValueId("v:acc")
local cond = Code.CodeValueId("v:cond")
local item = Code.CodeValueId("v:item")
local next_i = Code.CodeValueId("v:next_i")
local next_acc = Code.CodeValueId("v:next_acc")
local out = Code.CodeValueId("v:out")

local entry_id = Code.CodeBlockId("block:entry")
local header_id = Code.CodeBlockId("block:header")
local body_id = Code.CodeBlockId("block:body")
local exit_id = Code.CodeBlockId("block:exit")
local sig_id = Code.CodeSigId("sig:sum_i32")
local func_id = Code.CodeFuncId("fn:sum_i32")

local entry = Code.CodeBlock(
    entry_id,
    "entry",
    {},
    {
        inst("zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst("one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    },
    term("entry", Code.CodeTermJump(header_id, { zero, zero })),
    origin
)

local header = Code.CodeBlock(
    header_id,
    "header",
    {
        Code.CodeParam(i, "i", i32, origin),
        Code.CodeParam(acc, "acc", i32, origin),
    },
    {
        inst("cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    },
    term("header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })),
    origin
)

local body = Code.CodeBlock(
    body_id,
    "body",
    {},
    {
        inst("load", Code.CodeInstLoad(item, Code.CodePlaceIndex(Code.CodePlaceDeref(xs.value, i32, 4), i, i32, 4), access)),
        inst("sum", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
        inst("inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
    },
    term("body", Code.CodeTermJump(header_id, { next_i, next_acc })),
    origin
)

local exit = Code.CodeBlock(
    exit_id,
    "exit",
    { Code.CodeParam(out, "out", i32, origin) },
    {},
    term("exit", Code.CodeTermReturn({ out })),
    origin
)

local func = Code.CodeFunc(
    func_id,
    "sum_i32",
    Code.CodeLinkageExport,
    sig_id,
    { xs, n },
    {},
    entry_id,
    { entry, header, body, exit },
    origin
)

local module = Code.CodeModule(
    Code.CodeModuleId("module:luajit_lower_sum"),
    { Code.CodeSig(sig_id, { ptr_i32, i32 }, { i32 }) },
    {}, {}, {}, {},
    { func },
    origin
)
local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
})

local rejects = {}
local lj_module, facts, artifacts = Backend.lower_module(module, { contracts = contracts, collect_rejects = rejects })
assert(#rejects == 0, rejects[1] and rejects[1].reason or "unexpected LuaJIT lower reject")
assert(#facts.value.reductions == 1, "CodeValueFacts should derive one reduction")

local kplan
for _, plan in ipairs(facts.kernel.plans or {}) do
    if asdl.classof(plan) == Kernel.KernelPlanned then kplan = plan end
end
assert(kplan ~= nil, "CodeKernelPlan should produce a planned loop kernel")

local fn = lj_module.funcs[1]
assert(asdl.classof(fn.body) == LJ.LJBodyMachine, "kernel reduction should lower to a LuaJIT machine body")
assert(asdl.classof(fn.machines[1].op) == LJ.LJMachineStencilCall, "planned reduction should lower to a stencil call")
assert(#artifacts == 1, "planned reduction should produce one C stencil artifact")

local bank, bank_err = Backend.build_mc_bank(artifacts, { stem = "test_luajit_lower" })
assert(bank ~= nil, tostring(bank_err))
local compiled_result, compile_err, compile_src = Backend.compile_lj_module(lj_module, artifacts, {
    mc_bank = bank,
    chunk_name = "test_luajit_lower",
})
assert(compiled_result ~= nil, tostring(compile_err) .. "\n" .. tostring(compile_src))
local compiled = compiled_result.module

local count = 257
local arr = ffi.new("int32_t[?]", count)
local expected = 0
for j = 0, count - 1 do
    arr[j] = bit.tobit(j * 17 + 11)
    expected = bit.tobit(expected + arr[j])
end
assert(compiled.sum_i32(arr, count) == expected)

do
    local dst = param("dst", ptr_i32)
    local src = param("src", ptr_i32)
    local map_n = param("map_n", i32)
    local map_zero = Code.CodeValueId("v:map_zero")
    local map_one = Code.CodeValueId("v:map_one")
    local map_i = Code.CodeValueId("v:map_i")
    local map_cond = Code.CodeValueId("v:map_cond")
    local map_item = Code.CodeValueId("v:map_item")
    local map_value = Code.CodeValueId("v:map_value")
    local map_next_i = Code.CodeValueId("v:map_next_i")
    local map_entry_id = Code.CodeBlockId("block:map_entry")
    local map_header_id = Code.CodeBlockId("block:map_header")
    local map_body_id = Code.CodeBlockId("block:map_body")
    local map_exit_id = Code.CodeBlockId("block:map_exit")
    local map_sig_id = Code.CodeSigId("sig:map_store")
    local map_func_id = Code.CodeFuncId("fn:map_store")

    local function indexed(base)
        return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), map_i, i32, 4)
    end

    local map_entry = Code.CodeBlock(map_entry_id, "entry", {}, {
        inst("map_zero", Code.CodeInstConst(map_zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst("map_one", Code.CodeInstConst(map_one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term("map_entry", Code.CodeTermJump(map_header_id, { map_zero })), origin)

    local map_header = Code.CodeBlock(map_header_id, "header", {
        Code.CodeParam(map_i, "i", i32, origin),
    }, {
        inst("map_cond", Code.CodeInstCompare(map_cond, Core.CmpLt, i32, map_i, map_n.value)),
    }, term("map_header", Code.CodeTermBranch(map_cond, map_body_id, {}, map_exit_id, {})), origin)

    local map_body = Code.CodeBlock(map_body_id, "body", {}, {
        inst("map_load", Code.CodeInstLoad(map_item, indexed(src.value), access)),
        inst("map_neg", Code.CodeInstUnary(map_value, Core.UnaryNeg, i32, map_item)),
        inst("map_store", Code.CodeInstStore(indexed(dst.value), map_value, write_access)),
        inst("map_inc", Code.CodeInstBinary(map_next_i, Core.BinAdd, i32, sem, map_i, map_one)),
    }, term("map_body", Code.CodeTermJump(map_header_id, { map_next_i })), origin)

    local map_exit = Code.CodeBlock(map_exit_id, "exit", {}, {}, term("map_exit", Code.CodeTermReturn({})), origin)
    local map_func = Code.CodeFunc(map_func_id, "map_store", Code.CodeLinkageExport, map_sig_id, { dst, src, map_n }, {}, map_entry_id, { map_entry, map_header, map_body, map_exit }, origin)
    local map_module = Code.CodeModule(Code.CodeModuleId("module:map_store"), { Code.CodeSig(map_sig_id, { ptr_i32, ptr_i32, i32 }, {}) }, {}, {}, {}, {}, { map_func }, origin)
    local map_contracts = Code.CodeContractFactSet(map_module.id, {
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractBounds(dst.value, map_n.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractBounds(src.value, map_n.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractWriteonly(dst.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractReadonly(src.value), origin),
        Code.CodeFuncContractFact(map_func_id, Code.CodeContractDisjoint(dst.value, src.value), origin),
    })
    local map_rejects = {}
    local map_lj = Lower.lower_module(map_module, {
        contracts = map_contracts,
        collect_rejects = map_rejects,
        stencil_skeleton_artifact_for = function() return nil end,
    })
    assert(#map_rejects == 0, "original-control map loop should fall back without stencil reject: " .. tostring(map_rejects[1] and map_rejects[1].reason))
    assert(asdl.classof(map_lj.funcs[1].body) == LJ.LJBodyBlocks, "original-control map loop should keep block body")
end

local add_sig = Code.CodeSigId("sig:add")
local a = param("a", i32)
local b = param("b", i32)
local sum = Code.CodeValueId("v:sum")
local add_block_id = Code.CodeBlockId("block:add_entry")
local add_func = Code.CodeFunc(
    Code.CodeFuncId("fn:add"),
    "add",
    Code.CodeLinkageExport,
    add_sig,
    { a, b },
    {},
    add_block_id,
    {
        Code.CodeBlock(
            add_block_id,
            "add_entry",
            {},
            { inst("add_sum", Code.CodeInstBinary(sum, Core.BinAdd, i32, sem, a.value, b.value)) },
            term("add_ret", Code.CodeTermReturn({ sum })),
            origin
        ),
    },
    origin
)
local add_module = Code.CodeModule(Code.CodeModuleId("module:luajit_lower_add"), { Code.CodeSig(add_sig, { i32, i32 }, { i32 }) }, {}, {}, {}, {}, { add_func }, origin)
local add_lj = Lower.lower_module(add_module)
assert(asdl.classof(add_lj.funcs[1].body) == LJ.LJBodyBlocks, "non-kernel function should lower through block fallback")
local add_compiled, add_err, add_src = Emit.compile_module(add_lj, { chunk_name = "test_luajit_lower_add" })
assert(add_compiled ~= nil, tostring(add_err) .. "\n" .. tostring(add_src))
assert(add_compiled.add(12, 30) == 42)

io.write("lalin luajit_lower ok\n")
