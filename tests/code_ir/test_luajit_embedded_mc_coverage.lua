package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Stencil = T.LalinStencil
local Backend = require("lalin.luajit_backend")(T)
local InternSet = require("lalin.copy_patch_mc_intern_set")(T)
local Bank = require("lalin.copy_patch_mc")(T)

local origin = Code.CodeOriginGenerated("test_luajit_embedded_mc_coverage")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_i32 = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4) end

local intern_bank = assert(Bank.build_mc_bank(InternSet.artifacts(), {
    stem = "test_luajit_embedded_mc_coverage_bank",
    dir = "target/test_artifacts/test_luajit_embedded_mc_coverage",
    c_decls = InternSet.c_decls(),
    ffi_preamble = InternSet.ffi_preamble(),
}))

local embedded_by_symbol = {}
for _, entry in ipairs(intern_bank.entries or {}) do
    embedded_by_symbol[entry.symbol] = entry.artifact
end

local function assert_artifacts_covered(label, artifacts)
    assert(#artifacts > 0, label .. " should select at least one stencil artifact")
    for _, artifact in ipairs(artifacts) do
        if artifact.provider == Stencil.StencilProviderLuaTrace then
            assert(artifact.fingerprint and artifact.fingerprint.text, label .. " BC fallback artifact should carry a fingerprint")
        else
            local symbol = artifact.symbol.text
            local embedded = embedded_by_symbol[symbol]
            assert(embedded ~= nil, label .. " selected MC artifact missing from embedded intern bank: " .. symbol)
            assert(
                embedded.fingerprint.text == artifact.fingerprint.text,
                label .. " selected MC artifact fingerprint differs from embedded bank entry: " .. symbol
            )
        end
    end
end

local function lower_and_check(label, module, contracts)
    local _lj_module, _facts, artifacts, rejects = Backend.lower_module(module, { contracts = contracts })
    assert(#rejects == 0, label .. " should not reject stencil lowering: " .. tostring(rejects[1] and rejects[1].reason))
    assert_artifacts_covered(label, artifacts)
end

local function reduce_module()
    local xs = param("xs", ptr_i32)
    local n = param("n", i32)
    local zero = Code.CodeValueId("v:reduce:zero")
    local one = Code.CodeValueId("v:reduce:one")
    local i = Code.CodeValueId("v:reduce:i")
    local acc = Code.CodeValueId("v:reduce:acc")
    local cond = Code.CodeValueId("v:reduce:cond")
    local item = Code.CodeValueId("v:reduce:item")
    local next_i = Code.CodeValueId("v:reduce:next_i")
    local next_acc = Code.CodeValueId("v:reduce:next_acc")
    local out = Code.CodeValueId("v:reduce:out")
    local entry_id = Code.CodeBlockId("block:reduce:entry")
    local header_id = Code.CodeBlockId("block:reduce:header")
    local body_id = Code.CodeBlockId("block:reduce:body")
    local exit_id = Code.CodeBlockId("block:reduce:exit")
    local sig_id = Code.CodeSigId("sig:reduce")
    local func_id = Code.CodeFuncId("fn:reduce")

    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst("reduce:zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst("reduce:one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term("reduce:entry", Code.CodeTermJump(header_id, { zero, zero })), origin)
    local header = Code.CodeBlock(header_id, "header", {
        Code.CodeParam(i, "i", i32, origin),
        Code.CodeParam(acc, "acc", i32, origin),
    }, {
        inst("reduce:cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    }, term("reduce:header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
    local body = Code.CodeBlock(body_id, "body", {}, {
        inst("reduce:load", Code.CodeInstLoad(item, place(xs.value, i), read_i32)),
        inst("reduce:sum", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
        inst("reduce:inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
    }, term("reduce:body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term("reduce:exit", Code.CodeTermReturn({ out })), origin)
    local func = Code.CodeFunc(func_id, "reduce", Code.CodeLinkageExport, sig_id, { xs, n }, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:embedded_reduce"), { Code.CodeSig(sig_id, { ptr_i32, i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    local contracts = Code.CodeContractFactSet(module.id, {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(xs.value), origin),
    })
    return module, contracts
end

local function view_copy_module()
    local dst = param("view_dst", ptr_i32)
    local src = param("view_src", ptr_i32)
    local n = param("view_n", i32)
    local stride = param("view_stride", i32)
    local zero = Code.CodeValueId("v:view:zero")
    local one = Code.CodeValueId("v:view:one")
    local view = Code.CodeValueId("v:view:view")
    local data = Code.CodeValueId("v:view:data")
    local i = Code.CodeValueId("v:view:i")
    local cond = Code.CodeValueId("v:view:cond")
    local item = Code.CodeValueId("v:view:item")
    local next_i = Code.CodeValueId("v:view:next_i")
    local entry_id = Code.CodeBlockId("block:view:entry")
    local header_id = Code.CodeBlockId("block:view:header")
    local body_id = Code.CodeBlockId("block:view:body")
    local exit_id = Code.CodeBlockId("block:view:exit")
    local sig_id = Code.CodeSigId("sig:view_copy")
    local func_id = Code.CodeFuncId("fn:view_copy")

    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst("view:zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst("view:one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
        inst("view:make", Code.CodeInstViewMake(view, i32, src.value, n.value, stride.value)),
        inst("view:data", Code.CodeInstViewData(data, view)),
    }, term("view:entry", Code.CodeTermJump(header_id, { zero })), origin)
    local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin) }, {
        inst("view:cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    }, term("view:header", Code.CodeTermBranch(cond, body_id, {}, exit_id, {})), origin)
    local body = Code.CodeBlock(body_id, "body", {}, {
        inst("view:load", Code.CodeInstLoad(item, place(data, i), read_i32)),
        inst("view:store", Code.CodeInstStore(place(dst.value, i), item, write_i32)),
        inst("view:inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
    }, term("view:body", Code.CodeTermJump(header_id, { next_i })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", {}, {}, term("view:exit", Code.CodeTermReturn({})), origin)
    local func = Code.CodeFunc(func_id, "view_copy", Code.CodeLinkageExport, sig_id, { dst, src, n, stride }, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:embedded_view_copy"), { Code.CodeSig(sig_id, { ptr_i32, ptr_i32, i32, i32 }, {}) }, {}, {}, {}, {}, { func }, origin)
    local contracts = Code.CodeContractFactSet(module.id, {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, n.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(dst.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(src.value, n.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(src.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, src.value), origin),
    })
    return module, contracts
end

local reduce, reduce_contracts = reduce_module()
lower_and_check("contiguous reduce", reduce, reduce_contracts)

local view_copy, view_copy_contracts = view_copy_module()
lower_and_check("view copy", view_copy, view_copy_contracts)

io.write("lalin embedded mc coverage ok\n")
