-- Benchmark LalinCode -> luajit_lower stencil selection against direct binary stencil calls.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local Measure = require("lalin.luajit_measure")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local LJ = T.LalinLuaJIT
local Stencil = T.LalinStencil
local Value = T.LalinValue

local Lower = require("lalin.luajit_lower")(T)
local Emit = require("lalin.luajit_emit")(T)
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local CopyPatchMC = require("lalin.copy_patch_mc")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_LJ_LOWER_STENCIL_BENCH_N") or (full and "1000000" or "120000"))
local samples = tonumber(os.getenv("LALIN_LJ_LOWER_STENCIL_BENCH_SAMPLES") or (full and "5" or "3"))
local rounds = tonumber(os.getenv("LALIN_LJ_LOWER_STENCIL_BENCH_ROUNDS") or (full and "3" or "2"))
local cc = os.getenv("LALIN_LJ_LOWER_STENCIL_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("LALIN_LJ_LOWER_STENCIL_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"

local function stencil_object_cflags()
    return cflags .. " -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
end

local function compile_artifacts(artifacts, opts)
    opts = opts or {}
    opts.cc = opts.cc or cc
    opts.cflags = opts.cflags or stencil_object_cflags()
    local bank, bank_err, source = CopyPatchMC.build_mc_bank(artifacts, opts)
    if bank == nil then return nil, bank_err, source end
    local realization, realize_err = CopyPatchMC.realize_mc_artifacts(artifacts, {
        mc_bank = bank,
        preamble = opts.preamble,
        ffi_preamble = opts.ffi_preamble,
    })
    if realization == nil then return nil, realize_err, source end
    return { kind = "MCStencilBenchmarkBuild", bank = bank, realization = realization, symbols = realization.symbols, source = source }, nil, source
end

local origin = Code.CodeOriginGenerated("bench_luajit_lower_stencil_matrix")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function ptr(ty) return Code.CodeTyDataPtr(ty) end
local function bytes(ty)
    if ty == bool8 then return 1 end
    if pvm.classof(ty) == Code.CodeTyFloat and ty.bits == 64 then return 8 end
    return 4
end
local function access(mode, ty) return Code.CodeMemoryAccess(mode, ty, bytes(ty), Code.CodeMustNotTrap, false, nil) end
local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index, ty) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, ty, bytes(ty)), index, ty, bytes(ty)) end
local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function artifact_for(vocab, op, reduction, info)
    if vocab == Stencil.StencilCopy then return StencilArtifactPlan.copy_array_artifact(info) end
    if vocab == Stencil.StencilFill then return StencilArtifactPlan.fill_array_artifact(info) end
    if vocab == Stencil.StencilMap then return StencilArtifactPlan.map_array_artifact(op, info) end
    if vocab == Stencil.StencilZipMap then return StencilArtifactPlan.zip_map_array_artifact(op, info) end
    if vocab == Stencil.StencilCast then return StencilArtifactPlan.cast_array_artifact(op, info) end
    if vocab == Stencil.StencilCompare then return StencilArtifactPlan.compare_array_artifact(op, info) end
    if vocab == Stencil.StencilZipCompare then return StencilArtifactPlan.zip_compare_array_artifact(op, info) end
    if vocab == Stencil.StencilGather then return StencilArtifactPlan.gather_array_artifact(info) end
    if vocab == Stencil.StencilScatter then return StencilArtifactPlan.scatter_array_artifact(info) end
    if vocab == Stencil.StencilInPlaceMap then return StencilArtifactPlan.in_place_map_array_artifact(op, info) end
    if vocab == Stencil.StencilScan then return StencilArtifactPlan.scan_array_artifact(reduction, nil, info) end
    if vocab == Stencil.StencilFind then return StencilArtifactPlan.find_array_artifact(op, info) end
    if vocab == Stencil.StencilPartition then return StencilArtifactPlan.partition_array_artifact(op, info) end
    if vocab == Stencil.StencilReduce then return StencilArtifactPlan.reduce_array_artifact(reduction, nil, info) end
    if vocab == Stencil.StencilCount then return StencilArtifactPlan.count_array_artifact(op, info) end
    if vocab == Stencil.StencilMapReduce then return StencilArtifactPlan.map_reduce_array_artifact(op, reduction, nil, info) end
    if vocab == Stencil.StencilZipReduce then return StencilArtifactPlan.zip_reduce_array_artifact(op, reduction, nil, info) end
    error("unsupported benchmark vocab " .. tostring(vocab), 3)
end

local function build_store_case(kind, dst_ty)
    local name = "lower_" .. kind
    local dst = param(name .. "_dst", ptr(dst_ty))
    local src = param(name .. "_src", ptr(i32))
    local rhs = param(name .. "_rhs", ptr(i32))
    local idx = param(name .. "_idx", ptr(i32))
    local nparam = param(name .. "_n", i32)
    local value = param(name .. "_value", i32)
    local zero = Code.CodeValueId("v:" .. name .. ":zero")
    local one = Code.CodeValueId("v:" .. name .. ":one")
    local i = Code.CodeValueId("v:" .. name .. ":i")
    local cond = Code.CodeValueId("v:" .. name .. ":cond")
    local next_i = Code.CodeValueId("v:" .. name .. ":next_i")
    local item = Code.CodeValueId("v:" .. name .. ":item")
    local other = Code.CodeValueId("v:" .. name .. ":other")
    local index = Code.CodeValueId("v:" .. name .. ":index")
    local outv = Code.CodeValueId("v:" .. name .. ":out")
    local entry_id = Code.CodeBlockId("block:" .. name .. ":entry")
    local header_id = Code.CodeBlockId("block:" .. name .. ":header")
    local body_id = Code.CodeBlockId("block:" .. name .. ":body")
    local exit_id = Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id = Code.CodeSigId("sig:" .. name)
    local func_id = Code.CodeFuncId("fn:" .. name)
    local params = { dst, src, rhs, idx, nparam, value }
    if kind == "fill" then params = { dst, nparam, value }
    elseif kind == "copy" or kind == "copy_memmove" or kind == "map" then params = { dst, src, nparam }
    elseif kind == "zip_map" then params = { dst, src, rhs, nparam }
    elseif kind == "in_place_map" then params = { dst, nparam } end

    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero })), origin)
    local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin) }, {
        inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, nparam.value)),
    }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, {})), origin)

    local body_insts, store_index, store_ty = {}, i, dst_ty
    if kind == "fill" then
        outv = value.value
    elseif kind == "copy" or kind == "copy_memmove" then
        body_insts[#body_insts + 1] = inst(name .. ":load", Code.CodeInstLoad(outv, place(src.value, i, i32), access(Code.CodeMemoryRead, i32)))
    elseif kind == "map" then
        body_insts[#body_insts + 1] = inst(name .. ":load", Code.CodeInstLoad(item, place(src.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":neg", Code.CodeInstUnary(outv, Core.UnaryNeg, i32, item))
    elseif kind == "zip_map" then
        body_insts[#body_insts + 1] = inst(name .. ":load_l", Code.CodeInstLoad(item, place(src.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":load_r", Code.CodeInstLoad(other, place(rhs.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":add", Code.CodeInstBinary(outv, Core.BinAdd, i32, sem, item, other))
    elseif kind == "cast" then
        body_insts[#body_insts + 1] = inst(name .. ":load", Code.CodeInstLoad(item, place(src.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":cast", Code.CodeInstCast(outv, Core.MachineCastSToF, i32, f64, item))
    elseif kind == "compare" then
        body_insts[#body_insts + 1] = inst(name .. ":load", Code.CodeInstLoad(item, place(src.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":cmp", Code.CodeInstCompare(outv, Core.CmpGt, i32, item, zero))
    elseif kind == "zip_compare" then
        body_insts[#body_insts + 1] = inst(name .. ":load_l", Code.CodeInstLoad(item, place(src.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":load_r", Code.CodeInstLoad(other, place(rhs.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":cmp", Code.CodeInstCompare(outv, Core.CmpLt, i32, item, other))
    elseif kind == "gather" then
        body_insts[#body_insts + 1] = inst(name .. ":idx", Code.CodeInstLoad(index, place(idx.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":load", Code.CodeInstLoad(outv, place(src.value, index, i32), access(Code.CodeMemoryRead, i32)))
    elseif kind == "scatter" then
        body_insts[#body_insts + 1] = inst(name .. ":idx", Code.CodeInstLoad(index, place(idx.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":load", Code.CodeInstLoad(outv, place(src.value, i, i32), access(Code.CodeMemoryRead, i32)))
        store_index = index
    elseif kind == "in_place_map" then
        body_insts[#body_insts + 1] = inst(name .. ":load", Code.CodeInstLoad(item, place(dst.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":neg", Code.CodeInstUnary(outv, Core.UnaryNeg, i32, item))
        store_ty = i32
    else
        error("unknown store kind " .. tostring(kind), 2)
    end
    body_insts[#body_insts + 1] = inst(name .. ":store", Code.CodeInstStore(place(dst.value, store_index, store_ty), outv, access(Code.CodeMemoryWrite, store_ty)))
    body_insts[#body_insts + 1] = inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))

    local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(name .. ":body", Code.CodeTermJump(header_id, { next_i })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", {}, {}, term(name .. ":exit", Code.CodeTermReturn({})), origin)
    local sig_params = {}
    for j = 1, #params do sig_params[j] = params[j].ty end
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, params, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, sig_params, {}) }, {}, {}, {}, {}, { func }, origin)
    local facts = {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, nparam.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(dst.value), origin),
    }
    if kind == "in_place_map" then
        facts[2] = nil
    end
    local function read_ptr(p, disjoint)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(p.value, nparam.value), origin)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(p.value), origin)
        if disjoint ~= false then
            facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, p.value), origin)
        end
    end
    if kind == "copy" or kind == "copy_memmove" or kind == "map" then read_ptr(src, kind ~= "copy_memmove")
    elseif kind == "zip_map" then read_ptr(src); read_ptr(rhs); facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(src.value, rhs.value), origin)
    elseif kind ~= "fill" and kind ~= "in_place_map" then read_ptr(src); read_ptr(rhs); read_ptr(idx) end
    return module, Code.CodeContractFactSet(module.id, facts), name
end

local function build_reduce_case(kind)
    local name = "lower_" .. kind
    local xs, ys, nparam = param(name .. "_xs", ptr(i32)), param(name .. "_ys", ptr(i32)), param(name .. "_n", i32)
    local zero, one = Code.CodeValueId("v:" .. name .. ":zero"), Code.CodeValueId("v:" .. name .. ":one")
    local i, acc, cond = Code.CodeValueId("v:" .. name .. ":i"), Code.CodeValueId("v:" .. name .. ":acc"), Code.CodeValueId("v:" .. name .. ":cond")
    local item, other, mapped = Code.CodeValueId("v:" .. name .. ":item"), Code.CodeValueId("v:" .. name .. ":other"), Code.CodeValueId("v:" .. name .. ":mapped")
    local next_i, next_acc, out = Code.CodeValueId("v:" .. name .. ":next_i"), Code.CodeValueId("v:" .. name .. ":next_acc"), Code.CodeValueId("v:" .. name .. ":out")
    local entry_id, header_id, body_id, exit_id = Code.CodeBlockId("block:" .. name .. ":entry"), Code.CodeBlockId("block:" .. name .. ":header"), Code.CodeBlockId("block:" .. name .. ":body"), Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id, func_id = Code.CodeSigId("sig:" .. name), Code.CodeFuncId("fn:" .. name)
    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero, zero })), origin)
    local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin), Code.CodeParam(acc, "acc", i32, origin) }, {
        inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, nparam.value)),
    }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
    local body_insts = { inst(name .. ":load", Code.CodeInstLoad(item, place(xs.value, i, i32), access(Code.CodeMemoryRead, i32))) }
    local contribution = item
    if kind == "count" then
        body_insts[#body_insts + 1] = inst(name .. ":map", Code.CodeInstCompare(mapped, Core.CmpGt, i32, item, zero))
        contribution = mapped
    elseif kind == "map_reduce" then
        body_insts[#body_insts + 1] = inst(name .. ":map", Code.CodeInstUnary(mapped, Core.UnaryNeg, i32, item))
        contribution = mapped
    elseif kind == "zip_reduce" then
        body_insts[#body_insts + 1] = inst(name .. ":load_rhs", Code.CodeInstLoad(other, place(ys.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":map", Code.CodeInstBinary(mapped, Core.BinAdd, i32, sem, item, other))
        contribution = mapped
    end
    body_insts[#body_insts + 1] = inst(name .. ":reduce", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, contribution))
    body_insts[#body_insts + 1] = inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))
    local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(name .. ":body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term(name .. ":exit", Code.CodeTermReturn({ out })), origin)
    local params = kind == "zip_reduce" and { xs, ys, nparam } or { xs, nparam }
    local sig_params = kind == "zip_reduce" and { ptr(i32), ptr(i32), i32 } or { ptr(i32), i32 }
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, params, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, sig_params, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    local facts = { Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, nparam.value), origin) }
    if kind == "zip_reduce" then
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(ys.value, nparam.value), origin)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(xs.value, ys.value), origin)
    end
    return module, Code.CodeContractFactSet(module.id, facts), name
end

local function build_scan_case()
    local name = "lower_scan"
    local dst, xs, nparam = param(name .. "_dst", ptr(i32)), param(name .. "_xs", ptr(i32)), param(name .. "_n", i32)
    local zero, one = Code.CodeValueId("v:" .. name .. ":zero"), Code.CodeValueId("v:" .. name .. ":one")
    local i, acc, cond = Code.CodeValueId("v:" .. name .. ":i"), Code.CodeValueId("v:" .. name .. ":acc"), Code.CodeValueId("v:" .. name .. ":cond")
    local item, next_i, next_acc, out = Code.CodeValueId("v:" .. name .. ":item"), Code.CodeValueId("v:" .. name .. ":next_i"), Code.CodeValueId("v:" .. name .. ":next_acc"), Code.CodeValueId("v:" .. name .. ":out")
    local entry_id, header_id, body_id, exit_id = Code.CodeBlockId("block:" .. name .. ":entry"), Code.CodeBlockId("block:" .. name .. ":header"), Code.CodeBlockId("block:" .. name .. ":body"), Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id, func_id = Code.CodeSigId("sig:" .. name), Code.CodeFuncId("fn:" .. name)
    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero, zero })), origin)
    local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin), Code.CodeParam(acc, "acc", i32, origin) }, {
        inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, nparam.value)),
    }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
    local body = Code.CodeBlock(body_id, "body", {}, {
        inst(name .. ":load", Code.CodeInstLoad(item, place(xs.value, i, i32), access(Code.CodeMemoryRead, i32))),
        inst(name .. ":sum", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item)),
        inst(name .. ":store", Code.CodeInstStore(place(dst.value, i, i32), next_acc, access(Code.CodeMemoryWrite, i32))),
        inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
    }, term(name .. ":body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term(name .. ":exit", Code.CodeTermReturn({ out })), origin)
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, { dst, xs, nparam }, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, { ptr(i32), ptr(i32), i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    local facts = {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, nparam.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, nparam.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, xs.value), origin),
    }
    return module, Code.CodeContractFactSet(module.id, facts), name
end

local function build_find_case()
    local name = "lower_find"
    local xs, nparam = param(name .. "_xs", ptr(i32)), param(name .. "_n", i32)
    local zero, one, minus_one = Code.CodeValueId("v:" .. name .. ":zero"), Code.CodeValueId("v:" .. name .. ":one"), Code.CodeValueId("v:" .. name .. ":minus_one")
    local i, cond, item, predv = Code.CodeValueId("v:" .. name .. ":i"), Code.CodeValueId("v:" .. name .. ":cond"), Code.CodeValueId("v:" .. name .. ":item"), Code.CodeValueId("v:" .. name .. ":pred")
    local next_i, out = Code.CodeValueId("v:" .. name .. ":next_i"), Code.CodeValueId("v:" .. name .. ":out")
    local entry_id, header_id, body_id, latch_id, exit_id = Code.CodeBlockId("block:" .. name .. ":entry"), Code.CodeBlockId("block:" .. name .. ":header"), Code.CodeBlockId("block:" .. name .. ":body"), Code.CodeBlockId("block:" .. name .. ":latch"), Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id, func_id = Code.CodeSigId("sig:" .. name), Code.CodeFuncId("fn:" .. name)
    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
        inst(name .. ":minus_one", Code.CodeInstConst(minus_one, Code.CodeConstLiteral(i32, Core.LitInt("-1")))),
    }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero })), origin)
    local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin) }, {
        inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, nparam.value)),
    }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { minus_one })), origin)
    local body = Code.CodeBlock(body_id, "body", {}, {
        inst(name .. ":load", Code.CodeInstLoad(item, place(xs.value, i, i32), access(Code.CodeMemoryRead, i32))),
        inst(name .. ":pred", Code.CodeInstCompare(predv, Core.CmpGt, i32, item, zero)),
    }, term(name .. ":body", Code.CodeTermBranch(predv, exit_id, { i }, latch_id, {})), origin)
    local latch = Code.CodeBlock(latch_id, "latch", {}, {
        inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
    }, term(name .. ":latch", Code.CodeTermJump(header_id, { next_i })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term(name .. ":exit", Code.CodeTermReturn({ out })), origin)
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, { xs, nparam }, {}, entry_id, { entry, header, body, latch, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, { ptr(i32), i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    return module, Code.CodeContractFactSet(module.id, {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, nparam.value), origin),
    }), name
end

local function build_partition_case()
    local name = "lower_partition"
    local dst, xs, nparam = param(name .. "_dst", ptr(i32)), param(name .. "_xs", ptr(i32)), param(name .. "_n", i32)
    local zero, one = Code.CodeValueId("v:" .. name .. ":zero"), Code.CodeValueId("v:" .. name .. ":one")
    local i, out1, j, out2 = Code.CodeValueId("v:" .. name .. ":i"), Code.CodeValueId("v:" .. name .. ":out1"), Code.CodeValueId("v:" .. name .. ":j"), Code.CodeValueId("v:" .. name .. ":out2")
    local cond1, cond2 = Code.CodeValueId("v:" .. name .. ":cond1"), Code.CodeValueId("v:" .. name .. ":cond2")
    local item1, item2 = Code.CodeValueId("v:" .. name .. ":item1"), Code.CodeValueId("v:" .. name .. ":item2")
    local pred1, pred2 = Code.CodeValueId("v:" .. name .. ":pred1"), Code.CodeValueId("v:" .. name .. ":pred2")
    local next_i_a, next_i_b = Code.CodeValueId("v:" .. name .. ":next_i_a"), Code.CodeValueId("v:" .. name .. ":next_i_b")
    local next_j_a, next_j_b = Code.CodeValueId("v:" .. name .. ":next_j_a"), Code.CodeValueId("v:" .. name .. ":next_j_b")
    local next_out1, next_out2 = Code.CodeValueId("v:" .. name .. ":next_out1"), Code.CodeValueId("v:" .. name .. ":next_out2")
    local retv = Code.CodeValueId("v:" .. name .. ":ret")
    local entry_id, h1_id, b1_id, s1_id, l1_id = Code.CodeBlockId("block:" .. name .. ":entry"), Code.CodeBlockId("block:" .. name .. ":h1"), Code.CodeBlockId("block:" .. name .. ":b1"), Code.CodeBlockId("block:" .. name .. ":s1"), Code.CodeBlockId("block:" .. name .. ":l1")
    local h2_id, b2_id, s2_id, l2_id, exit_id = Code.CodeBlockId("block:" .. name .. ":h2"), Code.CodeBlockId("block:" .. name .. ":b2"), Code.CodeBlockId("block:" .. name .. ":s2"), Code.CodeBlockId("block:" .. name .. ":l2"), Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id, func_id = Code.CodeSigId("sig:" .. name), Code.CodeFuncId("fn:" .. name)
    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(name .. ":entry", Code.CodeTermJump(h1_id, { zero, zero })), origin)
    local h1 = Code.CodeBlock(h1_id, "h1", { Code.CodeParam(i, "i", i32, origin), Code.CodeParam(out1, "out1", i32, origin) }, {
        inst(name .. ":cond1", Code.CodeInstCompare(cond1, Core.CmpLt, i32, i, nparam.value)),
    }, term(name .. ":h1", Code.CodeTermBranch(cond1, b1_id, {}, h2_id, { zero, out1 })), origin)
    local b1 = Code.CodeBlock(b1_id, "b1", {}, {
        inst(name .. ":load1", Code.CodeInstLoad(item1, place(xs.value, i, i32), access(Code.CodeMemoryRead, i32))),
        inst(name .. ":pred1", Code.CodeInstCompare(pred1, Core.CmpGt, i32, item1, zero)),
    }, term(name .. ":b1", Code.CodeTermBranch(pred1, s1_id, {}, l1_id, {})), origin)
    local s1 = Code.CodeBlock(s1_id, "s1", {}, {
        inst(name .. ":store1", Code.CodeInstStore(place(dst.value, out1, i32), item1, access(Code.CodeMemoryWrite, i32))),
        inst(name .. ":next_out1", Code.CodeInstBinary(next_out1, Core.BinAdd, i32, sem, out1, one)),
        inst(name .. ":next_i_a", Code.CodeInstBinary(next_i_a, Core.BinAdd, i32, sem, i, one)),
    }, term(name .. ":s1", Code.CodeTermJump(h1_id, { next_i_a, next_out1 })), origin)
    local l1 = Code.CodeBlock(l1_id, "l1", {}, {
        inst(name .. ":next_i_b", Code.CodeInstBinary(next_i_b, Core.BinAdd, i32, sem, i, one)),
    }, term(name .. ":l1", Code.CodeTermJump(h1_id, { next_i_b, out1 })), origin)
    local h2 = Code.CodeBlock(h2_id, "h2", { Code.CodeParam(j, "j", i32, origin), Code.CodeParam(out2, "out2", i32, origin) }, {
        inst(name .. ":cond2", Code.CodeInstCompare(cond2, Core.CmpLt, i32, j, nparam.value)),
    }, term(name .. ":h2", Code.CodeTermBranch(cond2, b2_id, {}, exit_id, { out2 })), origin)
    local b2 = Code.CodeBlock(b2_id, "b2", {}, {
        inst(name .. ":load2", Code.CodeInstLoad(item2, place(xs.value, j, i32), access(Code.CodeMemoryRead, i32))),
        inst(name .. ":pred2", Code.CodeInstCompare(pred2, Core.CmpGt, i32, item2, zero)),
    }, term(name .. ":b2", Code.CodeTermBranch(pred2, l2_id, {}, s2_id, {})), origin)
    local s2 = Code.CodeBlock(s2_id, "s2", {}, {
        inst(name .. ":store2", Code.CodeInstStore(place(dst.value, out2, i32), item2, access(Code.CodeMemoryWrite, i32))),
        inst(name .. ":next_out2", Code.CodeInstBinary(next_out2, Core.BinAdd, i32, sem, out2, one)),
        inst(name .. ":next_j_a", Code.CodeInstBinary(next_j_a, Core.BinAdd, i32, sem, j, one)),
    }, term(name .. ":s2", Code.CodeTermJump(h2_id, { next_j_a, next_out2 })), origin)
    local l2 = Code.CodeBlock(l2_id, "l2", {}, {
        inst(name .. ":next_j_b", Code.CodeInstBinary(next_j_b, Core.BinAdd, i32, sem, j, one)),
    }, term(name .. ":l2", Code.CodeTermJump(h2_id, { next_j_b, out2 })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(retv, "ret", i32, origin) }, {}, term(name .. ":exit", Code.CodeTermReturn({ retv })), origin)
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, { dst, xs, nparam }, {}, entry_id, { entry, h1, b1, s1, l1, h2, b2, s2, l2, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, { ptr(i32), ptr(i32), i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    return module, Code.CodeContractFactSet(module.id, {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, nparam.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, nparam.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, xs.value), origin),
    }), name
end

local expected_vocab = {
    copy = Stencil.StencilCopy,
    copy_memmove = Stencil.StencilCopy,
    find = Stencil.StencilFind,
    partition = Stencil.StencilPartition,
    fill = Stencil.StencilFill,
    map = Stencil.StencilMap,
    zip_map = Stencil.StencilZipMap,
    cast = Stencil.StencilCast,
    compare = Stencil.StencilCompare,
    zip_compare = Stencil.StencilZipCompare,
    gather = Stencil.StencilGather,
    scatter = Stencil.StencilScatter,
    in_place_map = Stencil.StencilInPlaceMap,
    scan = Stencil.StencilScan,
    reduce = Stencil.StencilReduce,
    count = Stencil.StencilCount,
    map_reduce = Stencil.StencilMapReduce,
    zip_reduce = Stencil.StencilZipReduce,
}

local function compile_case(kind, is_reduce, dst_ty)
    local module, contracts, name
    local is_scan = kind == "scan"
    local is_find = kind == "find"
    local is_partition = kind == "partition"
    if is_scan then
        module, contracts, name = build_scan_case()
    elseif is_find then
        module, contracts, name = build_find_case()
    elseif is_partition then
        module, contracts, name = build_partition_case()
    elseif is_reduce then
        module, contracts, name = build_reduce_case(kind)
    else
        module, contracts, name = build_store_case(kind, dst_ty or i32)
    end
    local artifacts, rejects = {}, {}
    local lj_module = Lower.lower_module(module, {
        contracts = contracts,
        collect_rejects = rejects,
        stencil_store_artifact_for = (not is_reduce and not is_scan and not is_find and not is_partition) and function(func, vocab, op, plan, info)
            assert(vocab == expected_vocab[kind], name .. " selected wrong store vocab")
            local artifact = artifact_for(vocab, op, nil, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end or nil,
        stencil_skeleton_artifact_for = (not is_reduce) and function(func, vocab, op, reduction, plan, info)
            assert(vocab == expected_vocab[kind], name .. " selected wrong skeleton vocab")
            local artifact = artifact_for(vocab, op, reduction, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end or nil,
        stencil_reduce_artifact_for = is_reduce and function(func, vocab, op, reduction, plan, info)
            assert(vocab == expected_vocab[kind], name .. " selected wrong reduce vocab")
            local artifact = artifact_for(vocab, op, reduction, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end or nil,
    })
    local reject_msg = {}
    for i, reject in ipairs(rejects or {}) do reject_msg[i] = tostring(reject.reason) end
    assert(#artifacts == 1, name .. " should select one stencil artifact; rejects: " .. table.concat(reject_msg, " | "))
    local machine_kind = pvm.classof(lj_module.funcs[1].machines[1].kind)
    assert(machine_kind == ((is_reduce or is_scan or is_find or is_partition) and LJ.LJMachineStencilCall or LJ.LJMachineStencilEffect), name .. " should lower through stencil machine")
    local build, build_err, csrc = compile_artifacts(artifacts, {
        stem = "bench_luajit_lower_stencil_matrix_" .. sanitize(name),
        cc = cc,
        cflags = stencil_object_cflags(),
    })
    assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))
    local compiled, err, src = Emit.compile_module(lj_module, {
        chunk_name = "bench_luajit_lower_stencil_matrix_" .. name,
        stencil_symbols = build.symbols,
    })
    assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))
    return {
        name = name,
        kind = kind,
        lowered = compiled[name],
        raw = assert(build.symbols[artifacts[1].symbol.text], artifacts[1].symbol.text),
        artifact = artifacts[1],
    }
end

local xs = ffi.new("int32_t[?]", n)
local ys = ffi.new("int32_t[?]", n)
local idx = ffi.new("int32_t[?]", n)
local out = ffi.new("int32_t[?]", n)
local aux = ffi.new("int32_t[?]", n)
local mask = ffi.new("uint8_t[?]", n)
local dout = ffi.new("double[?]", n)
for i = 0, n - 1 do
    xs[i] = (i % 97) - 48
    ys[i] = (i % 53) + 3
    idx[i] = n - 1 - i
    aux[i] = xs[i]
end
local mid = math.floor(n / 2)

local compiled = {
    compile_case("copy", false, i32),
    compile_case("copy_memmove", false, i32),
    compile_case("fill", false, i32),
    compile_case("map", false, i32),
    compile_case("zip_map", false, i32),
    compile_case("cast", false, f64),
    compile_case("compare", false, bool8),
    compile_case("zip_compare", false, bool8),
    compile_case("gather", false, i32),
    compile_case("scatter", false, i32),
    compile_case("in_place_map", false, i32),
    compile_case("scan", false, i32),
    compile_case("find", false, i32),
    compile_case("partition", false, i32),
    compile_case("reduce", true, i32),
    compile_case("count", true, i32),
    compile_case("map_reduce", true, i32),
    compile_case("zip_reduce", true, i32),
}

local function lowered_fn(case)
    if case.kind == "copy" then return function() case.lowered(out, xs, n); return out[mid] end end
    if case.kind == "copy_memmove" then return function() case.lowered(out, xs, n); return out[mid] end end
    if case.kind == "fill" then return function() case.lowered(out, n, 7); return out[mid] end end
    if case.kind == "map" then return function() case.lowered(out, xs, n); return out[mid] end end
    if case.kind == "zip_map" then return function() case.lowered(out, xs, ys, n); return out[mid] end end
    if case.kind == "cast" then return function() case.lowered(dout, xs, ys, idx, n, 0); return dout[mid] end end
    if case.kind == "compare" then return function() case.lowered(mask, xs, ys, idx, n, 0); return mask[mid] end end
    if case.kind == "zip_compare" then return function() case.lowered(mask, xs, ys, idx, n, 0); return mask[mid] end end
    if case.kind == "gather" then return function() case.lowered(out, xs, ys, idx, n, 0); return out[mid] end end
    if case.kind == "scatter" then return function() case.lowered(out, xs, ys, idx, n, 0); return out[mid] end end
    if case.kind == "in_place_map" then return function() case.lowered(aux, n); case.lowered(aux, n); return aux[mid] end end
    if case.kind == "scan" then return function() return case.lowered(out, xs, n) end end
    if case.kind == "find" then return function() return case.lowered(xs, n) end end
    if case.kind == "partition" then return function() return case.lowered(out, xs, n) end end
    if case.kind == "reduce" then return function() return case.lowered(xs, n) end end
    if case.kind == "count" then return function() return case.lowered(xs, n) end end
    if case.kind == "map_reduce" then return function() return case.lowered(xs, n) end end
    if case.kind == "zip_reduce" then return function() return case.lowered(xs, ys, n) end end
    error("unknown lowered case " .. tostring(case.kind))
end

local function raw_fn(case)
    if case.kind == "copy" then return function() case.raw(out, xs, 0, n); return out[mid] end end
    if case.kind == "copy_memmove" then return function() case.raw(out, xs, 0, n); return out[mid] end end
    if case.kind == "fill" then return function() case.raw(out, 0, n, 7); return out[mid] end end
    if case.kind == "map" then return function() case.raw(out, xs, 0, n); return out[mid] end end
    if case.kind == "zip_map" then return function() case.raw(out, xs, ys, 0, n); return out[mid] end end
    if case.kind == "cast" then return function() case.raw(dout, xs, 0, n); return dout[mid] end end
    if case.kind == "compare" then return function() case.raw(mask, xs, 0, n); return mask[mid] end end
    if case.kind == "zip_compare" then return function() case.raw(mask, xs, ys, 0, n); return mask[mid] end end
    if case.kind == "gather" then return function() case.raw(out, xs, idx, 0, n); return out[mid] end end
    if case.kind == "scatter" then return function() case.raw(out, xs, idx, 0, n); return out[mid] end end
    if case.kind == "in_place_map" then return function() case.raw(aux, 0, n); case.raw(aux, 0, n); return aux[mid] end end
    if case.kind == "scan" then return function() return case.raw(out, xs, 0, n, 0) end end
    if case.kind == "find" then return function() return case.raw(xs, 0, n) end end
    if case.kind == "partition" then return function() return case.raw(out, xs, 0, n) end end
    if case.kind == "reduce" then return function() return case.raw(xs, 0, n, 0) end end
    if case.kind == "count" then return function() return case.raw(xs, 0, n) end end
    if case.kind == "map_reduce" then return function() return case.raw(xs, 0, n, 0) end end
    if case.kind == "zip_reduce" then return function() return case.raw(xs, ys, 0, n, 0) end end
    error("unknown raw case " .. tostring(case.kind))
end

local cases = {}
for _, case in ipairs(compiled) do
    cases[#cases + 1] = { name = "lowered " .. case.kind, fn = lowered_fn(case) }
    cases[#cases + 1] = { name = "raw " .. case.kind, fn = raw_fn(case) }
end

print(string.format("LalinCode -> LuaJIT stencil lowering benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
print("lowered vocabulary cells 18/18")
for _, result in ipairs(Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do print(Measure.format_result(result)) end
