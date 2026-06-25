package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local LJ = T.LalinLuaJIT
local Stencil = T.LalinStencil
local Exec = T.LalinExec
local Backend = require("lalin.luajit_backend")(T)

local origin = Code.CodeOriginGenerated("test_luajit_backend_binary")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4) end

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

local entry = Code.CodeBlock(entry_id, "entry", {}, {
    inst("zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst("one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
}, term("entry", Code.CodeTermJump(header_id, { zero, zero })), origin)

local header = Code.CodeBlock(header_id, "header", {
    Code.CodeParam(i, "i", i32, origin),
    Code.CodeParam(acc, "acc", i32, origin),
}, {
    inst("cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
}, term("header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)

local body = Code.CodeBlock(body_id, "body", {}, {
    inst("load", Code.CodeInstLoad(item, place(xs.value, i), read_i32)),
    inst("sum", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
    inst("inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
}, term("body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)

local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term("exit", Code.CodeTermReturn({ out })), origin)
local func = Code.CodeFunc(func_id, "sum_i32", Code.CodeLinkageExport, sig_id, { xs, n }, {}, entry_id, { entry, header, body, exit }, origin)
local module = Code.CodeModule(Code.CodeModuleId("module:luajit_backend_binary"), { Code.CodeSig(sig_id, { ptr_i32, i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(xs.value), origin),
})

local lj_module, facts, artifacts, rejects = Backend.lower_module(module, {
    contracts = contracts,
})
assert(#rejects == 0, rejects[1] and rejects[1].reason or "unexpected backend reject")
local bank, bank_err, bank_src = Backend.build_binary_bank(artifacts, { stem = "test_luajit_backend_binary" })
assert(bank ~= nil, tostring(bank_err) .. "\n" .. tostring(bank_src))
local result, err, src = Backend.compile_lj_module(lj_module, artifacts, {
    bank = bank,
    chunk_name = "test_luajit_backend_binary",
})
assert(result ~= nil, tostring(err) .. "\n" .. tostring(src))
result.artifacts = artifacts
result.facts = facts
assert(#artifacts == 1, "expected one selected stencil artifact")
assert(artifacts[1].instance.descriptor.vocab == Stencil.StencilReduce, "expected reduce stencil")
assert(pvm.classof(facts.luajit_stencil_machines) == LJ.LJStencilMachineModulePlan, "expected ASDL LuaJIT stencil machine plan")
assert(#facts.luajit_stencil_machines.machines == 1, "expected one planned LuaJIT stencil machine")
assert(facts.luajit_stencil_machines.machines[1].artifact == artifacts[1], "planned LuaJIT stencil machine should reference selected artifact")
assert(pvm.classof(facts.exec_plan) == Exec.ExecModulePlan, "expected ASDL exec plan")
assert(#facts.exec_plan.entries == 1, "expected one exec stencil decision")
assert(pvm.classof(facts.exec_plan.entries[1].decision) == Exec.ExecMaterializeStencil, "selected artifact should materialize an exec stencil fragment")
assert(facts.exec_plan.entries[1].decision.fragment.kind.artifact == artifacts[1], "exec materialization should reference selected artifact")
assert(result.realization.kind == "BinaryStencilBankRealization", "expected binary bank realization")
assert(#result.realization.installed == 1, "expected one installed binary stencil")

local count = 1024
local arr = ffi.new("int32_t[?]", count)
local expected = 0
for j = 0, count - 1 do
    arr[j] = bit.tobit(j * 13 + 7)
    expected = bit.tobit(expected + arr[j])
end
assert(result.module.sum_i32(arr, count) == expected)

io.write("lalin luajit_backend binary ok\n")
