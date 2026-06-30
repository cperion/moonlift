package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local LLBL = require("llbl")
local C = require("llbl.c")
local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Host = T.LalinHost
local LJ = T.LalinLuaJIT
local Sem = T.LalinSem
local Stencil = T.LalinStencil
local Ty = T.LalinType
local Value = T.LalinValue

local Lower = require("lalin.luajit_lower")(T)
local Emit = require("lalin.luajit_emit")(T)
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local Backend = require("lalin.luajit_backend")(T)
local StencilBinary = require("tests.code_ir.residual_mc_helper")

local origin = Code.CodeOriginGenerated("test_luajit_lower_stencil_fields")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ty_i32 = Ty.TScalar(Core.ScalarI32)
local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local ptr_pair = Code.CodeTyDataPtr(pair_ty)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_i32 = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)
local right_field = Sem.FieldByOffset("right", 4, ty_i32, Host.HostRepScalar(Core.ScalarI32))

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end

local function pair_right_place(base, index)
    local item = Code.CodePlaceIndex(Code.CodePlaceDeref(base, pair_ty, 4), index, pair_ty, 8)
    return Code.CodePlaceField(item, right_field, i32, 4, 4, 4)
end

local function i32_place(base, index)
    return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4)
end

local function access_named(desc, name)
    for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(desc)) do
        if access.name == name then return access end
    end
    error("missing descriptor access " .. tostring(name))
end

local function assert_field_layout(artifact, label)
    for _, access in ipairs(StencilArtifactPlan.descriptor_accesses(artifact.instance.descriptor)) do
        local layout = access.layout
        if asdl.classof(layout) == Stencil.StencilLayoutFieldProjection
            and layout.record_ty == pair_ty
            and layout.field_name == "right"
            and layout.field_offset == 4 then
            assert(asdl.classof(layout.parent) == Stencil.StencilLayoutContiguous, label .. " should keep parent layout")
            return access
        end
    end
    error("missing field descriptor access for " .. tostring(label))
end

local xs = param("xs", ptr_pair)
local dst = param("dst", ptr_i32)
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

local sum_entry_id = Code.CodeBlockId("block:sum_pair_right:entry")
local sum_header_id = Code.CodeBlockId("block:sum_pair_right:header")
local sum_body_id = Code.CodeBlockId("block:sum_pair_right:body")
local sum_exit_id = Code.CodeBlockId("block:sum_pair_right:exit")
local sum_sig_id = Code.CodeSigId("sig:sum_pair_right")
local sum_func_id = Code.CodeFuncId("fn:sum_pair_right")

local sum_entry = Code.CodeBlock(sum_entry_id, "entry", {}, {
    inst("sum:zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst("sum:one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
}, term("sum:entry", Code.CodeTermJump(sum_header_id, { zero, zero })), origin)

local sum_header = Code.CodeBlock(sum_header_id, "header", {
    Code.CodeParam(i, "i", i32, origin),
    Code.CodeParam(acc, "acc", i32, origin),
}, {
    inst("sum:cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
}, term("sum:header", Code.CodeTermBranch(cond, sum_body_id, {}, sum_exit_id, { acc })), origin)

local sum_body = Code.CodeBlock(sum_body_id, "body", {}, {
    inst("sum:load", Code.CodeInstLoad(item, pair_right_place(xs.value, i), read_i32)),
    inst("sum:add", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
    inst("sum:inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
}, term("sum:body", Code.CodeTermJump(sum_header_id, { next_i, next_acc })), origin)

local sum_exit = Code.CodeBlock(sum_exit_id, "exit", {
    Code.CodeParam(out, "out", i32, origin),
}, {}, term("sum:exit", Code.CodeTermReturn({ out })), origin)

local sum_func = Code.CodeFunc(sum_func_id, "sum_pair_right", Code.CodeLinkageExport, sum_sig_id, { xs, n }, {}, sum_entry_id, {
    sum_entry,
    sum_header,
    sum_body,
    sum_exit,
}, origin)

local mi = Code.CodeValueId("v:map_i")
local mcond = Code.CodeValueId("v:map_cond")
local mitem = Code.CodeValueId("v:map_item")
local mneg = Code.CodeValueId("v:map_neg")
local mnext_i = Code.CodeValueId("v:map_next_i")
local map_entry_id = Code.CodeBlockId("block:neg_pair_right:entry")
local map_header_id = Code.CodeBlockId("block:neg_pair_right:header")
local map_body_id = Code.CodeBlockId("block:neg_pair_right:body")
local map_exit_id = Code.CodeBlockId("block:neg_pair_right:exit")
local map_sig_id = Code.CodeSigId("sig:neg_pair_right")
local map_func_id = Code.CodeFuncId("fn:neg_pair_right")

local map_entry = Code.CodeBlock(map_entry_id, "entry", {}, {
    inst("map:zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
    inst("map:one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
}, term("map:entry", Code.CodeTermJump(map_header_id, { zero })), origin)

local map_header = Code.CodeBlock(map_header_id, "header", {
    Code.CodeParam(mi, "i", i32, origin),
}, {
    inst("map:cond", Code.CodeInstCompare(mcond, Core.CmpLt, i32, mi, n.value)),
}, term("map:header", Code.CodeTermBranch(mcond, map_body_id, {}, map_exit_id, {})), origin)

local map_body = Code.CodeBlock(map_body_id, "body", {}, {
    inst("map:load", Code.CodeInstLoad(mitem, pair_right_place(xs.value, mi), read_i32)),
    inst("map:neg", Code.CodeInstUnary(mneg, Core.UnaryNeg, i32, mitem)),
    inst("map:store", Code.CodeInstStore(i32_place(dst.value, mi), mneg, write_i32)),
    inst("map:inc", Code.CodeInstBinary(mnext_i, Core.BinAdd, i32, sem, mi, one)),
}, term("map:body", Code.CodeTermJump(map_header_id, { mnext_i })), origin)

local map_exit = Code.CodeBlock(map_exit_id, "exit", {}, {}, term("map:exit", Code.CodeTermReturn({})), origin)
local map_func = Code.CodeFunc(map_func_id, "neg_pair_right", Code.CodeLinkageExport, map_sig_id, { dst, xs, n }, {}, map_entry_id, {
    map_entry,
    map_header,
    map_body,
    map_exit,
}, origin)

local module = Code.CodeModule(Code.CodeModuleId("module:stencil_fields"), {
    Code.CodeSig(sum_sig_id, { ptr_pair, i32 }, { i32 }),
    Code.CodeSig(map_sig_id, { ptr_i32, ptr_pair, i32 }, {}),
}, {}, {}, {}, {}, { sum_func, map_func }, origin)

local contracts = Code.CodeContractFactSet(module.id, {
    Code.CodeFuncContractFact(sum_func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    Code.CodeFuncContractFact(sum_func_id, Code.CodeContractReadonly(xs.value), origin),
    Code.CodeFuncContractFact(map_func_id, Code.CodeContractBounds(dst.value, n.value), origin),
    Code.CodeFuncContractFact(map_func_id, Code.CodeContractWriteonly(dst.value), origin),
    Code.CodeFuncContractFact(map_func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    Code.CodeFuncContractFact(map_func_id, Code.CodeContractReadonly(xs.value), origin),
    Code.CodeFuncContractFact(map_func_id, Code.CodeContractDisjoint(dst.value, xs.value), origin),
})

local artifacts, rejects = {}, {}
local lj_module, facts = Lower.lower_module(module, {
    contracts = contracts,
    collect_rejects = rejects,
    stencil_reduce_artifact_for = function(func, vocab, op, reduction, plan, descriptor)
        local artifact = Backend.artifact_for(vocab, op, reduction, plan, descriptor)
        artifacts[#artifacts + 1] = artifact
        return artifact
    end,
    stencil_store_artifact_for = function(func, vocab, op, plan, descriptor)
        local artifact = Backend.artifact_for(vocab, op, nil, plan, descriptor)
        artifacts[#artifacts + 1] = artifact
        return artifact
    end,
})

local function plan_summary()
    local out = {}
    for _, plan in ipairs(facts.kernel.plans or {}) do
        local rejects = plan:kernel_plan_rejects()
        out[#out + 1] = tostring(asdl.classof(plan)) .. ":" .. tostring(rejects and rejects[1] and rejects[1].reason or "ok")
    end
    return table.concat(out, ",")
end

assert(#rejects == 0, "field stencil rejected: " .. tostring(rejects[1] and rejects[1].reason) .. " plans=" .. plan_summary())
assert(#artifacts == 2, "field lowering should select reduce and map artifacts")
assert(asdl.classof(lj_module.funcs[1].body) == LJ.LJBodyMachine, "sum should lower to machine body")
assert(asdl.classof(lj_module.funcs[2].body) == LJ.LJBodyMachine, "map should lower to machine body")

local reduce_access = assert_field_layout(artifacts[1], "reduce")
local map_access = assert_field_layout(artifacts[2], "map")
assert(reduce_access.ty == i32 and map_access.ty == i32, "field accesses should expose field element type")

local ffi_preamble = "typedef struct { int32_t left; int32_t right; } Demo_Pair;"
local c_decls = {
    C.typedef_struct [LLBL.N.Demo_Pair] {
        LLBL.N.left [C.i32],
        LLBL.N.right [C.i32],
    },
}
local build, build_err, csrc = StencilBinary.compile(T, artifacts, {
    stem = "test_luajit_lower_stencil_fields",
    c_decls = c_decls,
    ffi_preamble = ffi_preamble,
})
assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))

local compiled, err, src = Emit.compile_module(lj_module, {
    chunk_name = "test_luajit_lower_stencil_fields",
    stencil_symbols = build.symbols,
})
assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))

local pairs = ffi.new("Demo_Pair[4]")
pairs[0].left, pairs[0].right = 1, 10
pairs[1].left, pairs[1].right = 2, 20
pairs[2].left, pairs[2].right = 3, -5
pairs[3].left, pairs[3].right = 4, 7

local out_arr = ffi.new("int32_t[4]")
assert(compiled.sum_pair_right(pairs, 4) == 32, "lowered field reduce")
compiled.neg_pair_right(out_arr, pairs, 4)
assert(out_arr[0] == -10 and out_arr[1] == -20 and out_arr[2] == 5 and out_arr[3] == -7, "lowered field map")

io.write("lalin luajit_lower_stencil_fields ok\n")
