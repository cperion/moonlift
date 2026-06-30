package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local lalin = require("lalin")
local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local LJ = T.LalinLuaJIT
local Stencil = T.LalinStencil
local Exec = T.LalinExec
local Backend = require("lalin.luajit_backend")(T)

local origin = Code.CodeOriginGenerated("test_luajit_backend_mc")
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
local module = Code.CodeModule(Code.CodeModuleId("module:luajit_backend_mc"), { Code.CodeSig(sig_id, { ptr_i32, i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(xs.value), origin),
})

local lj_module, facts, artifacts, rejects = Backend.lower_module(module, {
    contracts = contracts,
})
assert(#rejects == 0, rejects[1] and rejects[1].reason or "unexpected backend reject")
local bank, bank_err, bank_src = Backend.build_mc_bank(artifacts, { stem = "test_luajit_backend_mc" })
assert(bank ~= nil, tostring(bank_err) .. "\n" .. tostring(bank_src))
local result, err, src = Backend.compile_lj_module(lj_module, artifacts, {
    mc_bank = bank,
    chunk_name = "test_luajit_backend_mc",
})
assert(result ~= nil, tostring(err) .. "\n" .. tostring(src))
result.artifacts = artifacts
result.facts = facts
assert(#artifacts == 1, "expected one selected stencil artifact")
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
assert(StencilArtifactPlan.descriptor_vocab(artifacts[1].instance.descriptor) == Stencil.StencilReduce, "expected reduce stencil")
assert(artifacts[1].fingerprint.text:match("^stencil%-artifact%-v1:"), "MC artifact should carry a build fingerprint")
local selection = facts.stencil.selections[1].selection
assert(asdl.classof(selection) == Stencil.StencilSelected, "expected selected stencil fact")
assert(selection.provenance.winner == selection.provenance.candidates[1].name, "selection provenance should name the winning candidate")
assert(selection.provenance.candidates[1].status == Stencil.StencilScheduleCandidateSelected, "first schedule candidate should be selected")
assert(selection.provenance.candidates[1].cost > 0, "selected candidate should carry a positive cost")
assert(#selection.provenance.candidates >= 2, "autovector selection should record scalar fallback candidate")
assert(selection.provenance.candidates[2].status == Stencil.StencilScheduleCandidateViable, "fallback candidate should remain viable")
assert(asdl.classof(facts.luajit_stencil_machines) == LJ.LJStencilMachineModulePlan, "expected ASDL LuaJIT stencil machine plan")
assert(#facts.luajit_stencil_machines.machines == 1, "expected one planned LuaJIT stencil machine")
assert(facts.luajit_stencil_machines.machines[1].artifact == artifacts[1], "planned LuaJIT stencil machine should reference selected artifact")
assert(asdl.classof(facts.exec_plan) == Exec.ExecModulePlan, "expected ASDL exec plan")
assert(#facts.exec_plan.entries == 1, "expected one exec stencil decision")
assert(asdl.classof(facts.exec_plan.entries[1].decision) == Exec.ExecMaterializeStencil, "selected artifact should materialize an exec stencil fragment")
assert(facts.exec_plan.entries[1].decision.fragment.body.artifact == artifacts[1], "exec materialization should reference selected artifact")
assert(result.realization.kind == "MCStencilBankRealization", "expected mc bank realization")
assert(#result.realization.installed == 1, "expected one installed mc stencil")
local installed_artifact = result.realization.installed[1].entry.artifact
assert(#installed_artifact.diagnostics >= 2, "MC realized artifact should carry construction and compiler diagnostics")
local saw_compiler_diagnostic = false
for _, diagnostic in ipairs(installed_artifact.diagnostics or {}) do
    if diagnostic.source == "compiler" then saw_compiler_diagnostic = true end
end
assert(saw_compiler_diagnostic, "MC realized artifact should carry compiler diagnostics")
local stale_artifact = Stencil.StencilArtifact(
    artifacts[1].instance,
    artifacts[1].provider,
    artifacts[1].symbol,
    artifacts[1].c_signature,
    Stencil.StencilArtifactFingerprint(artifacts[1].fingerprint.text .. ":stale"),
    artifacts[1].realized,
    artifacts[1].diagnostics or {},
    artifacts[1].schedule_rejects or {}
)
local stale_realization, stale_err = Backend.realize_artifacts({ stale_artifact }, { mc_bank = bank })
assert(stale_realization == nil, "stale MC bank entry must not realize")
assert(tostring(stale_err):match("fingerprint mismatch"), "stale MC bank rejection should name fingerprint mismatch")

local count = 1024
local arr = ffi.new("int32_t[?]", count)
local expected = 0
for j = 0, count - 1 do
    arr[j] = bit.tobit(j * 13 + 7)
    expected = bit.tobit(expected + arr[j])
end
assert(result.module.sum_i32(arr, count) == expected)

local facade_src = [=[
local zip_add = fn(dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  requires disjoint(dst)(lhs), disjoint(dst)(rhs), disjoint(lhs)(rhs)
  loop i in 0 .. n do
    dst[i] = lhs[i] + rhs[i]
  end
end

return { zip_add }
]=]
local parsed = assert(lalin.loadstring(facade_src, "@test_luajit_backend_mc_facade.lln"))()
local facade_plan = lalin.plan_luajit_artifact(parsed, { name = "BackendMCFacade" })
local facade_bank, facade_bank_err, facade_bank_src = facade_plan.backend.build_mc_bank(facade_plan.artifacts, {
    stem = "test_luajit_backend_mc_facade",
})
assert(facade_bank ~= nil, tostring(facade_bank_err) .. "\n" .. tostring(facade_bank_src))
local facade = lalin.compile("BackendMCFacade", parsed, {
    mc_bank = facade_bank,
})
assert(facade.__lalin_artifact.residual == "mc", "public compile should default to MC")
assert(facade.__lalin_artifact.mc_bank == facade_bank, "public compile should use the supplied MC bank")
local lhs = ffi.new("int32_t[3]", { 1, 2, 3 })
local rhs = ffi.new("int32_t[3]", { 10, 20, 30 })
local dst = ffi.new("int32_t[3]")
facade.zip_add(dst, lhs, rhs, 3)
assert(dst[0] == 11 and dst[1] == 22 and dst[2] == 33, "public compile MC result mismatch")

io.write("lalin luajit_backend mc ok\n")
