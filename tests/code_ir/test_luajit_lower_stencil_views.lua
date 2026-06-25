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

local origin = Code.CodeOriginGenerated("test_luajit_lower_stencil_views")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_i32 = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4) end

local function access_named(desc, name)
    for _, access in ipairs(desc.accesses or {}) do
        if access.name == name then return access end
    end
    error("missing descriptor access " .. tostring(name))
end

local dst = param("dst", ptr_i32)
local src = param("src", ptr_i32)
local n = param("n", i32)
local s = param("stride", i32)

local zero = Code.CodeValueId("v:zero")
local one = Code.CodeValueId("v:one")
local view = Code.CodeValueId("v:view")
local data = Code.CodeValueId("v:view_data")
local i = Code.CodeValueId("v:i")
local cond = Code.CodeValueId("v:cond")
local item = Code.CodeValueId("v:item")
local next_i = Code.CodeValueId("v:next_i")

local entry_id = Code.CodeBlockId("block:entry")
local header_id = Code.CodeBlockId("block:header")
local body_id = Code.CodeBlockId("block:body")
local exit_id = Code.CodeBlockId("block:exit")
local sig_id = Code.CodeSigId("sig:view_copy")
local func_id = Code.CodeFuncId("fn:view_copy")

local entry = Code.CodeBlock(entry_id, "entry", {}, {
    inst("zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst("one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    inst("view", Code.CodeInstViewMake(view, i32, src.value, n.value, s.value)),
    inst("view_data", Code.CodeInstViewData(data, view)),
}, term("entry", Code.CodeTermJump(header_id, { zero })), origin)

local header = Code.CodeBlock(header_id, "header", {
    Code.CodeParam(i, "i", i32, origin),
}, {
    inst("cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
}, term("header", Code.CodeTermBranch(cond, body_id, {}, exit_id, {})), origin)

local body = Code.CodeBlock(body_id, "body", {}, {
    inst("load", Code.CodeInstLoad(item, place(data, i), read_i32)),
    inst("store", Code.CodeInstStore(place(dst.value, i), item, write_i32)),
    inst("inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
}, term("body", Code.CodeTermJump(header_id, { next_i })), origin)

local exit = Code.CodeBlock(exit_id, "exit", {}, {}, term("exit", Code.CodeTermReturn({})), origin)
local func = Code.CodeFunc(func_id, "view_copy", Code.CodeLinkageExport, sig_id, { dst, src, n, s }, {}, entry_id, { entry, header, body, exit }, origin)
local module = Code.CodeModule(Code.CodeModuleId("module:view_copy"), { Code.CodeSig(sig_id, { ptr_i32, ptr_i32, i32, i32 }, {}) }, {}, {}, {}, {}, { func }, origin)
local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(dst.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(src.value, n.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(src.value), origin),
    Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, src.value), origin),
})

local artifacts, rejects = {}, {}
local lj_module, facts = Lower.lower_module(module, {
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

local function plan_summary()
    local out = {}
    for _, plan in ipairs(facts.kernel.plans or {}) do
        local subject = plan.subject and tostring(pvm.classof(plan.subject)) or "no-subject"
        local result = plan.body and plan.body.result and tostring(pvm.classof(plan.body.result)) or "no-result"
        local effects = plan.body and #(plan.body.effects or {}) or 0
        out[#out + 1] = tostring(pvm.classof(plan)) .. "/" .. subject .. "/" .. result .. "/effects=" .. tostring(effects)
        if plan.rejects ~= nil and plan.rejects[1] ~= nil then
            out[#out + 1] = ":" .. tostring(plan.rejects[1].reason)
        end
    end
    return table.concat(out, ",")
end

assert(#rejects == 0, "view copy rejected: " .. tostring(rejects[1] and rejects[1].reason) .. " plans=" .. plan_summary())
assert(#artifacts == 1, "view copy should select one stencil artifact")
assert(pvm.classof(lj_module.funcs[1].body) == LJ.LJBodyMachine, "view copy should lower to a stencil machine")

local src_access = access_named(artifacts[1].instance.descriptor, "src")
local src_topology = src_access.topology
assert(pvm.classof(src_topology) == Stencil.StencilTopologyViewDescriptor, "source access should keep view descriptor topology")
assert(src_topology.view == view)
assert(src_topology.data == src.value)
assert(src_topology.len == n.value)
assert(src_topology.stride == s.value)
assert(src_topology.stride_const == nil)

local build, build_err, csrc = StencilBinary.compile(T, artifacts, { stem = "test_luajit_lower_stencil_views" })
assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))
local compiled, err, src_lua = Emit.compile_module(lj_module, {
    chunk_name = "test_luajit_lower_stencil_views",
    stencil_symbols = build.symbols,
})
assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src_lua))

local xs = ffi.new("int32_t[12]", { 3, 99, 5, 99, -1, 99, 8, 99, 13, 99, 21, 99 })
local out = ffi.new("int32_t[6]")
compiled.view_copy(out, xs, 6, 2)
for j = 0, 5 do assert(out[j] == xs[j * 2], "view copy mismatch at " .. tostring(j)) end

io.write("lalin luajit_lower_stencil_views ok\n")
