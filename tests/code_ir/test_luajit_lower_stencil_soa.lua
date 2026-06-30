package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local LJ = T.LalinLuaJIT
local Stencil = T.LalinStencil
local Ty = T.LalinType
local Value = T.LalinValue

local Lower = require("lalin.luajit_lower")(T)
local Emit = require("lalin.luajit_emit")(T)
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local Backend = require("lalin.luajit_backend")(T)
local StencilBinary = require("tests.code_ir.residual_mc_helper")

local origin = Code.CodeOriginGenerated("test_luajit_lower_stencil_soa")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local record_ty = Code.CodeTyNamed("Demo", "PairSoA", Ty.TNamed(Ty.TypeRefGlobal("Demo", "PairSoA")))
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_i32 = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4) end

local dst = param("dst", ptr_i32)
local left = param("left", ptr_i32)
local right = param("right", ptr_i32)
local n = param("n", i32)

local zero = Code.CodeValueId("v:zero")
local one = Code.CodeValueId("v:one")

local zi = Code.CodeValueId("v:zip_i")
local zcond = Code.CodeValueId("v:zip_cond")
local zl = Code.CodeValueId("v:zip_left")
local zr = Code.CodeValueId("v:zip_right")
local zsum = Code.CodeValueId("v:zip_sum")
local znext = Code.CodeValueId("v:zip_next")

local zip_entry_id = Code.CodeBlockId("block:soa_zip_add:entry")
local zip_header_id = Code.CodeBlockId("block:soa_zip_add:header")
local zip_body_id = Code.CodeBlockId("block:soa_zip_add:body")
local zip_exit_id = Code.CodeBlockId("block:soa_zip_add:exit")
local zip_sig_id = Code.CodeSigId("sig:soa_zip_add")
local zip_func_id = Code.CodeFuncId("fn:soa_zip_add")

local zip_entry = Code.CodeBlock(zip_entry_id, "entry", {}, {
    inst("zip:zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst("zip:one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
}, term("zip:entry", Code.CodeTermJump(zip_header_id, { zero })), origin)

local zip_header = Code.CodeBlock(zip_header_id, "header", { Code.CodeParam(zi, "i", i32, origin) }, {
    inst("zip:cond", Code.CodeInstCompare(zcond, Core.CmpLt, i32, zi, n.value)),
}, term("zip:header", Code.CodeTermBranch(zcond, zip_body_id, {}, zip_exit_id, {})), origin)

local zip_body = Code.CodeBlock(zip_body_id, "body", {}, {
    inst("zip:load_left", Code.CodeInstLoad(zl, place(left.value, zi), read_i32)),
    inst("zip:load_right", Code.CodeInstLoad(zr, place(right.value, zi), read_i32)),
    inst("zip:add", Code.CodeInstBinary(zsum, Core.BinAdd, i32, sem, zl, zr)),
    inst("zip:store", Code.CodeInstStore(place(dst.value, zi), zsum, write_i32)),
    inst("zip:inc", Code.CodeInstBinary(znext, Core.BinAdd, i32, sem, zi, one)),
}, term("zip:body", Code.CodeTermJump(zip_header_id, { znext })), origin)

local zip_exit = Code.CodeBlock(zip_exit_id, "exit", {}, {}, term("zip:exit", Code.CodeTermReturn({})), origin)
local zip_func = Code.CodeFunc(zip_func_id, "soa_zip_add", Code.CodeLinkageExport, zip_sig_id, { dst, left, right, n }, {}, zip_entry_id, {
    zip_entry,
    zip_header,
    zip_body,
    zip_exit,
}, origin)

local ri = Code.CodeValueId("v:red_i")
local racc = Code.CodeValueId("v:red_acc")
local rcond = Code.CodeValueId("v:red_cond")
local rl = Code.CodeValueId("v:red_left")
local rr = Code.CodeValueId("v:red_right")
local rsum = Code.CodeValueId("v:red_sum")
local rnext_acc = Code.CodeValueId("v:red_next_acc")
local rnext_i = Code.CodeValueId("v:red_next_i")
local rout = Code.CodeValueId("v:red_out")

local red_entry_id = Code.CodeBlockId("block:soa_zip_sum:entry")
local red_header_id = Code.CodeBlockId("block:soa_zip_sum:header")
local red_body_id = Code.CodeBlockId("block:soa_zip_sum:body")
local red_exit_id = Code.CodeBlockId("block:soa_zip_sum:exit")
local red_sig_id = Code.CodeSigId("sig:soa_zip_sum")
local red_func_id = Code.CodeFuncId("fn:soa_zip_sum")

local red_entry = Code.CodeBlock(red_entry_id, "entry", {}, {
    inst("red:zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst("red:one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
}, term("red:entry", Code.CodeTermJump(red_header_id, { zero, zero })), origin)

local red_header = Code.CodeBlock(red_header_id, "header", {
    Code.CodeParam(ri, "i", i32, origin),
    Code.CodeParam(racc, "acc", i32, origin),
}, {
    inst("red:cond", Code.CodeInstCompare(rcond, Core.CmpLt, i32, ri, n.value)),
}, term("red:header", Code.CodeTermBranch(rcond, red_body_id, {}, red_exit_id, { racc })), origin)

local red_body = Code.CodeBlock(red_body_id, "body", {}, {
    inst("red:load_left", Code.CodeInstLoad(rl, place(left.value, ri), read_i32)),
    inst("red:load_right", Code.CodeInstLoad(rr, place(right.value, ri), read_i32)),
    inst("red:sum", Code.CodeInstBinary(rsum, Core.BinAdd, i32, sem, rl, rr)),
    inst("red:add_acc", Code.CodeInstBinary(rnext_acc, Core.BinAdd, i32, sem, racc, rsum)),
    inst("red:inc", Code.CodeInstBinary(rnext_i, Core.BinAdd, i32, sem, ri, one)),
}, term("red:body", Code.CodeTermJump(red_header_id, { rnext_i, rnext_acc })), origin)

local red_exit = Code.CodeBlock(red_exit_id, "exit", {
    Code.CodeParam(rout, "out", i32, origin),
}, {}, term("red:exit", Code.CodeTermReturn({ rout })), origin)
local red_func = Code.CodeFunc(red_func_id, "soa_zip_sum", Code.CodeLinkageExport, red_sig_id, { left, right, n }, {}, red_entry_id, {
    red_entry,
    red_header,
    red_body,
    red_exit,
}, origin)

local module = Code.CodeModule(Code.CodeModuleId("module:stencil_soa"), {
    Code.CodeSig(zip_sig_id, { ptr_i32, ptr_i32, ptr_i32, i32 }, {}),
    Code.CodeSig(red_sig_id, { ptr_i32, ptr_i32, i32 }, { i32 }),
}, {}, {}, {}, {}, { zip_func, red_func }, origin)

local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractBounds(dst.value, n.value), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractWriteonly(dst.value), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractSoAComponent(dst.value, record_ty, "sum", 2), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractBounds(left.value, n.value), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractReadonly(left.value), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractSoAComponent(left.value, record_ty, "left", 0), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractBounds(right.value, n.value), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractReadonly(right.value), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractSoAComponent(right.value, record_ty, "right", 1), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractDisjoint(dst.value, left.value), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractDisjoint(dst.value, right.value), origin),
    Code.CodeFuncContractFact(zip_func_id, Code.CodeContractDisjoint(left.value, right.value), origin),

    Code.CodeFuncContractFact(red_func_id, Code.CodeContractBounds(left.value, n.value), origin),
    Code.CodeFuncContractFact(red_func_id, Code.CodeContractReadonly(left.value), origin),
    Code.CodeFuncContractFact(red_func_id, Code.CodeContractSoAComponent(left.value, record_ty, "left", 0), origin),
    Code.CodeFuncContractFact(red_func_id, Code.CodeContractBounds(right.value, n.value), origin),
    Code.CodeFuncContractFact(red_func_id, Code.CodeContractReadonly(right.value), origin),
    Code.CodeFuncContractFact(red_func_id, Code.CodeContractSoAComponent(right.value, record_ty, "right", 1), origin),
    Code.CodeFuncContractFact(red_func_id, Code.CodeContractDisjoint(left.value, right.value), origin),
})

local artifacts, rejects = {}, {}
local lj_module, facts = Lower.lower_module(module, {
    contracts = contracts,
    collect_rejects = rejects,
    stencil_store_artifact_for = function(func, vocab, op, plan, descriptor)
        local artifact = Backend.artifact_for(vocab, op, nil, plan, descriptor)
        artifacts[#artifacts + 1] = artifact
        return artifact
    end,
    stencil_reduce_artifact_for = function(func, vocab, op, reduction, plan, descriptor)
        local artifact = Backend.artifact_for(vocab, op, reduction, plan, descriptor)
        artifacts[#artifacts + 1] = artifact
        return artifact
    end,
})

assert(#rejects == 0, "SoA lowering rejected: " .. tostring(rejects[1] and rejects[1].reason))
assert(#artifacts == 2, "SoA lowering should select StoreN and ReduceN artifacts")
assert(asdl.classof(lj_module.funcs[1].body) == LJ.LJBodyMachine, "StoreN SoA store should lower to machine body")
assert(asdl.classof(lj_module.funcs[2].body) == LJ.LJBodyMachine, "ReduceN SoA fold should lower to machine body")

local function assert_soa(access, field_name, component_index)
    local top = access.layout
    assert(asdl.classof(top) == Stencil.StencilLayoutSoAComponent, access.name .. " should keep SoA layout")
    assert(top.record_ty == record_ty, access.name .. " should keep record type")
    assert(top.field_name == field_name, access.name .. " should keep field name")
    assert(top.component_index == component_index, access.name .. " should keep component index")
end

local function access_named(desc, name)
    for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
        if access.name == name then return access end
    end
    error("missing descriptor access " .. tostring(name))
end

local function access_soa(desc, field_name, component_index)
    for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
        local layout = access.layout
        if asdl.classof(layout) == Stencil.StencilLayoutSoAComponent
            and layout.field_name == field_name
            and layout.component_index == component_index then
            return access
        end
    end
    error("missing SoA descriptor access " .. tostring(field_name))
end

assert_soa(access_named(artifacts[1].instance.descriptor, "dst"), "sum", 2)
assert_soa(access_soa(artifacts[1].instance.descriptor, "left", 0), "left", 0)
assert_soa(access_soa(artifacts[1].instance.descriptor, "right", 1), "right", 1)
assert_soa(access_soa(artifacts[2].instance.descriptor, "left", 0), "left", 0)
assert_soa(access_soa(artifacts[2].instance.descriptor, "right", 1), "right", 1)

local build, build_err, csrc = StencilBinary.compile(T, artifacts, {
    stem = "test_luajit_lower_stencil_soa",
})
assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))

local compiled, err, src = Emit.compile_module(lj_module, {
    chunk_name = "test_luajit_lower_stencil_soa",
    stencil_symbols = build.symbols,
})
assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))

local left_arr = ffi.new("int32_t[5]", { 1, -2, 5, 0, 3 })
local right_arr = ffi.new("int32_t[5]", { 10, 20, -5, 7, 4 })
local out_arr = ffi.new("int32_t[5]")

compiled.soa_zip_add(out_arr, left_arr, right_arr, 5)
assert(out_arr[0] == 11 and out_arr[1] == 18 and out_arr[2] == 0 and out_arr[3] == 7 and out_arr[4] == 7, "lowered SoA zip map")
assert(compiled.soa_zip_sum(left_arr, right_arr, 5) == 43, "lowered SoA zip reduce")

io.write("lalin luajit_lower_stencil_soa ok\n")
