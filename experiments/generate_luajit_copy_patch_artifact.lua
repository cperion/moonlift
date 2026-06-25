package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local ffi = require("ffi")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Backend = require("lalin.luajit_backend")(T)

local origin = Code.CodeOriginGenerated("generate_luajit_copy_patch_artifact")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4) end

local function build_reduce_module()
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
  local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin), Code.CodeParam(acc, "acc", i32, origin) }, {
    inst("cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
  }, term("header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
  local body = Code.CodeBlock(body_id, "body", {}, {
    inst("load", Code.CodeInstLoad(item, place(xs.value, i), read_i32)),
    inst("sum", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
    inst("inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
  }, term("body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
  local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term("exit", Code.CodeTermReturn({ out })), origin)
  local func = Code.CodeFunc(func_id, "sum_i32", Code.CodeLinkageExport, sig_id, { xs, n }, {}, entry_id, { entry, header, body, exit }, origin)
  local module = Code.CodeModule(Code.CodeModuleId("module:copy_patch_artifact"), { Code.CodeSig(sig_id, { ptr_i32, i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
  local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(xs.value), origin),
  })
  return module, contracts
end

local module, contracts = build_reduce_module()
local lj_module, facts, artifacts, rejects = Backend.lower_module(module, { contracts = contracts })
assert(#rejects == 0, rejects[1] and rejects[1].reason or "unexpected reject")
local bank = assert(Backend.build_binary_bank(artifacts, { stem = "generated_copy_patch_artifact" }))
local path = arg[1] or "target/artifacts/sum_i32_copy_patch_artifact.lua"
assert(Backend.emit_lua_artifact(lj_module, artifacts, {
  bank = bank,
  path = path,
  chunk_name = "generated_copy_patch_artifact",
}))

local loaded = assert(loadfile(path))()
local count = 16
local arr = ffi.new("int32_t[?]", count)
local expected = 0
for i = 0, count - 1 do arr[i] = i + 1; expected = expected + arr[i] end
assert(loaded.sum_i32(arr, count) == expected)
print(path)
