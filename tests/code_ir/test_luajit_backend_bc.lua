package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local lalin = require("lalin")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Stencil = T.LalinStencil
local Backend = require("lalin.luajit_backend")(T)

local origin = Code.CodeOriginGenerated("test_luajit_backend_bc")
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
local module = Code.CodeModule(Code.CodeModuleId("module:luajit_backend_bc"), { Code.CodeSig(sig_id, { ptr_i32, i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(xs.value), origin),
})

local result, err, src = Backend.compile_module(module, {
    contracts = contracts,
    copy_patch = "bc",
    chunk_name = "test_luajit_backend_bc",
})
assert(result ~= nil, tostring(err) .. "\n" .. tostring(src))
assert(#result.artifacts == 1, "expected one selected stencil artifact")
assert(result.artifacts[1].provider == Stencil.StencilProviderLuaTrace, "expected BC stencil provider")
assert(result.artifacts[1].fingerprint.text:match("^stencil%-artifact%-v1:"), "BC artifact should carry a build fingerprint")
assert(result.realization.kind == "BCStencilBankRealization", "expected BC copy-patch realization")
assert(result.realization.bc_bank ~= nil, "expected LuaTrace BC bank")
local artifact_source, artifact_err = Backend.emit_lua_artifact(result.lj_module, result.artifacts, {
    copy_patch = "bc",
    chunk_name = "test_luajit_backend_bc_artifact",
})
assert(artifact_source ~= nil, tostring(artifact_err))
assert(artifact_source:match("LuaTrace BC copy%-patch artifact"), "expected LuaTrace BC copy-patch artifact header")
assert(artifact_source:match("__ml_load_bc"), "expected embedded bytecode loader")
assert(not artifact_source:match("local function ml_stencil_reduce_array_i32_add_to_i32_s1"), "bytecode artifact should not embed LuaTrace source function")
assert(not artifact_source:match("__ml_install"), "LuaTrace artifact must not install copy-patch MC stencils")

local count = 1024
local arr = ffi.new("int32_t[?]", count)
local expected = 0
for j = 0, count - 1 do
    arr[j] = bit.tobit(j * 13 + 7)
    expected = bit.tobit(expected + arr[j])
end
assert(result.module.sum_i32(arr, count) == expected)

local loader = loadstring or load
local artifact_chunk, load_err = loader(artifact_source, "@test_luajit_backend_bc_artifact")
assert(artifact_chunk ~= nil, tostring(load_err) .. "\n" .. artifact_source)
local artifact_module = artifact_chunk()
assert(artifact_module.sum_i32(arr, count) == expected)

local dsl_sum = lalin.loadstring([=[
return fn. sum_i32 { xs [ptr [i32]], n [i32] } [i32] {
  requires { bounds(xs, n), readonly(xs) },

  entry. start {} { jump. loop { i = 0, acc = 0 }, },

  block. loop { i [i32], acc [i32] } {
    when (i :lt (n)) {
      jump. body { i = i, acc = acc },
    },

    jump. done { acc = acc },
  },

  block. body { i [i32], acc [i32] } {
    jump. loop { i = i + 1, acc = acc + xs[i] },
  },

  block. done { acc [i32] } {
    ret (acc),
  },
}
]=], "test_luajit_backend_bc_dsl.lua")

local dsl_artifact = lalin.emit_luajit_artifact(dsl_sum, {
    name = "test_luajit_backend_bc_dsl_artifact",
    copy_patch = "bc",
})
assert(dsl_artifact.source:match("LuaTrace BC copy%-patch artifact"), "facade should emit LuaTrace BC artifact")
assert(dsl_artifact.bc_bank ~= nil, "facade should expose LuaTrace BC bank")
assert(not dsl_artifact.source:match("local function ml_stencil_reduce_array_i32_add_to_i32_s1"), "facade bytecode artifact should not emit LuaTrace source")
assert(not dsl_artifact.source:match("__ml_install"), "facade LuaTrace artifact must not build/install an MC bank")
local dsl_chunk, dsl_load_err = loader(dsl_artifact.source, "@test_luajit_backend_bc_dsl_artifact")
assert(dsl_chunk ~= nil, tostring(dsl_load_err) .. "\n" .. dsl_artifact.source)
local dsl_module = dsl_chunk()
assert(dsl_module.sum_i32(arr, count) == expected)

io.write("lalin luajit_backend bc ok\n")
