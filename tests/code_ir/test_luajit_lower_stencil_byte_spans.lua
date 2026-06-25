package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local LJ = T.LalinLuaJIT
local Stencil = T.LalinStencil

local Lower = require("lalin.luajit_lower")(T)
local Emit = require("lalin.luajit_emit")(T)
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local StencilBinary = require("tests.code_ir.stencil_binary_helper")

local origin = Code.CodeOriginGenerated("test_luajit_lower_stencil_byte_spans")
local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_u8 = Code.CodeTyDataPtr(u8)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_u8 = Code.CodeMemoryAccess(Code.CodeMemoryRead, u8, 1, Code.CodeMustNotTrap, false, nil)
local write_u8 = Code.CodeMemoryAccess(Code.CodeMemoryWrite, u8, 1, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, u8, 1), index, u8, 1) end

local function access_named(desc, name)
    for _, access in ipairs(desc.accesses or {}) do
        if access.name == name then return access end
    end
    error("missing descriptor access " .. tostring(name))
end

local dst = param("dst", ptr_u8)
local src = param("src", ptr_u8)
local n = param("n", i32)

local zero = Code.CodeValueId("v:zero")
local one = Code.CodeValueId("v:one")
local span = Code.CodeValueId("v:span")
local data = Code.CodeValueId("v:span_data")
local i = Code.CodeValueId("v:i")
local cond = Code.CodeValueId("v:cond")
local item = Code.CodeValueId("v:item")
local next_i = Code.CodeValueId("v:next_i")

local entry_id = Code.CodeBlockId("block:entry")
local header_id = Code.CodeBlockId("block:header")
local body_id = Code.CodeBlockId("block:body")
local exit_id = Code.CodeBlockId("block:exit")
local sig_id = Code.CodeSigId("sig:bytespan_copy")
local func_id = Code.CodeFuncId("fn:bytespan_copy")

local entry = Code.CodeBlock(entry_id, "entry", {}, {
    inst("zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst("one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    inst("span", Code.CodeInstByteSpanMake(span, src.value, n.value)),
    inst("span_data", Code.CodeInstByteSpanData(data, span)),
}, term("entry", Code.CodeTermJump(header_id, { zero })), origin)

local header = Code.CodeBlock(header_id, "header", {
    Code.CodeParam(i, "i", i32, origin),
}, {
    inst("cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
}, term("header", Code.CodeTermBranch(cond, body_id, {}, exit_id, {})), origin)

local body = Code.CodeBlock(body_id, "body", {}, {
    inst("load", Code.CodeInstLoad(item, place(data, i), read_u8)),
    inst("store", Code.CodeInstStore(place(dst.value, i), item, write_u8)),
    inst("inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
}, term("body", Code.CodeTermJump(header_id, { next_i })), origin)

local exit = Code.CodeBlock(exit_id, "exit", {}, {}, term("exit", Code.CodeTermReturn({})), origin)
local func = Code.CodeFunc(func_id, "bytespan_copy", Code.CodeLinkageExport, sig_id, { dst, src, n }, {}, entry_id, { entry, header, body, exit }, origin)
local module = Code.CodeModule(Code.CodeModuleId("module:bytespan_copy"), { Code.CodeSig(sig_id, { ptr_u8, ptr_u8, i32 }, {}) }, {}, {}, {}, {}, { func }, origin)
local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(dst.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(src.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(src.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, src.value), origin),
})

local artifacts, rejects = {}, {}
local lj_module = Lower.lower_module(module, {
    contracts = contracts,
    collect_rejects = rejects,
    stencil_store_artifact_for = function(func_, vocab, op, plan, info)
        assert(vocab == Stencil.StencilCopy)
        local artifact = StencilArtifactPlan.copy_array_artifact(info)
        artifacts[#artifacts + 1] = artifact
        return artifact
    end,
    stencil_skeleton_artifact_for = function(func_, vocab, op, reduction, plan, info)
        assert(vocab == Stencil.StencilCopy)
        local artifact = StencilArtifactPlan.copy_array_artifact(info)
        artifacts[#artifacts + 1] = artifact
        return artifact
    end,
})

assert(#rejects == 0, "byte span copy rejected: " .. tostring(rejects[1] and rejects[1].reason))
assert(#artifacts == 1, "byte span copy should select one stencil artifact")
assert(pvm.classof(lj_module.funcs[1].body) == LJ.LJBodyMachine, "byte span copy should lower to a stencil machine")

local src_topology = access_named(artifacts[1].instance.descriptor, "src").topology
assert(pvm.classof(src_topology) == Stencil.StencilTopologyByteSpanDescriptor, "source access should keep byte span topology")
assert(src_topology.span == span)
assert(src_topology.data == src.value)
assert(src_topology.len == n.value)

local build, build_err, csrc = StencilBinary.compile(T, artifacts, { stem = "test_luajit_lower_stencil_byte_spans" })
assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))
local compiled, err, src_lua = Emit.compile_module(lj_module, {
    chunk_name = "test_luajit_lower_stencil_byte_spans",
    stencil_symbols = build.symbols,
})
assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src_lua))

local xs = ffi.new("uint8_t[6]", { 3, 5, 255, 8, 13, 21 })
local out = ffi.new("uint8_t[6]")
compiled.bytespan_copy(out, xs, 6)
for j = 0, 5 do assert(out[j] == xs[j], "byte span copy mismatch at " .. tostring(j)) end

io.write("lalin luajit_lower_stencil_byte_spans ok\n")
