package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local LJ = T.MoonLuaJIT
local Kernel = T.MoonKernel

local Lower = require("moonlift.luajit_lower")(T)
local Emit = require("moonlift.luajit_emit")(T)
local Backend = require("moonlift.luajit_backend")(T)

local origin = Code.CodeOriginGenerated("test_luajit_lower")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)

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
    if pvm.classof(plan) == Kernel.KernelPlanned then kplan = plan end
end
assert(kplan ~= nil, "CodeKernelPlan should produce a planned loop kernel")

local fn = lj_module.funcs[1]
assert(pvm.classof(fn.body) == LJ.LJBodyMachine, "kernel reduction should lower to a LuaJIT machine body")
assert(pvm.classof(fn.machines[1].kind) == LJ.LJMachineStencilCall, "planned reduction should lower to a stencil call")
assert(#artifacts == 1, "planned reduction should produce one C stencil artifact")

local bank, bank_err = Backend.build_binary_bank(artifacts, { stem = "test_luajit_lower" })
assert(bank ~= nil, tostring(bank_err))
local compiled_result, compile_err, compile_src = Backend.compile_lj_module(lj_module, artifacts, {
    bank = bank,
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
assert(pvm.classof(add_lj.funcs[1].body) == LJ.LJBodyBlocks, "non-kernel function should lower through block fallback")
local add_compiled, add_err, add_src = Emit.compile_module(add_lj, { chunk_name = "test_luajit_lower_add" })
assert(add_compiled ~= nil, tostring(add_err) .. "\n" .. tostring(add_src))
assert(add_compiled.add(12, 30) == 42)

io.write("moonlift luajit_lower ok\n")
