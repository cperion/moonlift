package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Graph = T.LalinGraph
local Kernel = T.LalinKernel
local LJ = T.LalinLuaJIT
local Stencil = T.LalinStencil
local Value = T.LalinValue

local Lower = require("lalin.luajit_lower")(T)
local Emit = require("lalin.luajit_emit")(T)
local CodeGraph = require("lalin.code_graph")(T)
local CodeFlowFacts = require("lalin.code_flow_facts")(T)
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local Backend = require("lalin.luajit_backend")(T)
local StencilBinary = require("tests.code_ir.residual_mc_helper")

local origin = Code.CodeOriginGenerated("test_luajit_lower_stencil_extended")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local f64 = Code.CodeTyFloat(64)
local bool8 = Code.CodeTyBool8
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function ptr(ty) return Code.CodeTyDataPtr(ty) end
local function bytes(ty)
    if ty == bool8 then return 1 end
    if asdl.classof(ty) == Code.CodeTyFloat and ty.bits == 64 then return 8 end
    return 4
end
local function access(mode, ty) return Code.CodeMemoryAccess(mode, ty, bytes(ty), Code.CodeMustNotTrap, false, nil) end
local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index, ty) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, ty, bytes(ty)), index, ty, bytes(ty)) end

local function store_provider(func, vocab, op, plan, descriptor)
    return Backend.artifact_for(vocab, op, nil, plan, descriptor)
end

local function reduce_provider(func, vocab, op, reduction, plan, descriptor)
    return Backend.artifact_for(vocab, op, reduction, plan, descriptor)
end

local function compile_module(module, contracts, opts)
    local artifacts, rejects = {}, {}
    local lj_module = Lower.lower_module(module, {
        contracts = contracts,
        flow = opts.flow,
        collect_rejects = rejects,
        stencil_store_artifact_for = opts.store and function(func, vocab, op, plan, descriptor)
            local artifact = store_provider(func, vocab, op, plan, descriptor)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end or nil,
        stencil_reduce_artifact_for = opts.reduce and function(func, vocab, op, reduction, plan, descriptor)
            local artifact = reduce_provider(func, vocab, op, reduction, plan, descriptor)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end or nil,
    })
    assert(#rejects == 0, opts.name .. " rejected: " .. tostring(rejects[1] and rejects[1].reason))
    assert(#artifacts == 1, opts.name .. " should select one artifact")
    assert(StencilArtifactPlan.descriptor_vocab(artifacts[1].instance.descriptor) == opts.basis, opts.name .. " selected wrong basis vocab")
    local producer = StencilArtifactPlan.descriptor_producer(artifacts[1].instance.descriptor)
    local shape = StencilArtifactPlan.producer_shape(producer)
    local expected_producer = opts.producer or Stencil.StencilProduceRange1D
    assert(asdl.classof(shape) == expected_producer, opts.name .. " should feed the expected typed producer from lowering")
    if expected_producer == Stencil.StencilProduceRange1D then
        assert(shape.start == nil and shape.stop == nil, opts.name .. " producer bounds should be runtime call arguments, not descriptor identity")
    end
    assert(asdl.classof(lj_module.funcs[1].machines[1].op) == (opts.reduce and LJ.LJMachineStencilCall or LJ.LJMachineStencilEffect), opts.name .. " should lower through stencil machine")
    local build, build_err, csrc = StencilBinary.compile(T, artifacts, { stem = "test_luajit_lower_stencil_extended_" .. opts.name })
    assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))
    local compiled, err, src = Emit.compile_module(lj_module, {
        chunk_name = "test_luajit_lower_stencil_extended_" .. opts.name,
        stencil_symbols = build.symbols,
    })
    assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))
    return compiled[opts.name]
end

local function store_case(kind, dst_ty)
    local name = "lower_" .. kind
    local dst = param("dst", ptr(dst_ty))
    local src = param("src", ptr(i32))
    local rhs = param("rhs", ptr(i32))
    local idx = param("idx", ptr(i32))
    local n = param("n", i32)
    local zero, one = Code.CodeValueId("v:" .. name .. ":zero"), Code.CodeValueId("v:" .. name .. ":one")
    local i, cond, next_i = Code.CodeValueId("v:" .. name .. ":i"), Code.CodeValueId("v:" .. name .. ":cond"), Code.CodeValueId("v:" .. name .. ":next_i")
    local item, other, index, outv = Code.CodeValueId("v:" .. name .. ":item"), Code.CodeValueId("v:" .. name .. ":other"), Code.CodeValueId("v:" .. name .. ":index"), Code.CodeValueId("v:" .. name .. ":out")
    local entry_id, header_id, body_id, exit_id = Code.CodeBlockId("block:" .. name .. ":entry"), Code.CodeBlockId("block:" .. name .. ":header"), Code.CodeBlockId("block:" .. name .. ":body"), Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id, func_id = Code.CodeSigId("sig:" .. name), Code.CodeFuncId("fn:" .. name)
    local params = { dst, src, rhs, idx, n }
    if kind == "in_place_map" then params = { dst, n } end

    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero })), origin)
    local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin) }, {
        inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, {})), origin)

    local body_insts, store_index, store_ty = {}, i, dst_ty
    if kind == "cast" then
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
    end
    body_insts[#body_insts + 1] = inst(name .. ":store", Code.CodeInstStore(place(dst.value, store_index, store_ty), outv, access(Code.CodeMemoryWrite, store_ty)))
    body_insts[#body_insts + 1] = inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))

    local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(name .. ":body", Code.CodeTermJump(header_id, { next_i })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", {}, {}, term(name .. ":exit", Code.CodeTermReturn({})), origin)
    local sig_params = {}
    for i = 1, #params do sig_params[i] = params[i].ty end
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, params, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, sig_params, {}) }, {}, {}, {}, {}, { func }, origin)
    local facts = { Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, n.value), origin) }
    local function read_ptr(p)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(p.value, n.value), origin)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, p.value), origin)
    end
    if kind ~= "in_place_map" then read_ptr(src); read_ptr(rhs); read_ptr(idx) end
    return module, Code.CodeContractFactSet(module.id, facts), name
end

local function reduction_case(kind)
    local name = "lower_" .. kind
    local xs, ys, n = param("xs", ptr(i32)), param("ys", ptr(i32)), param("n", i32)
    local zero, one = Code.CodeValueId("v:" .. name .. ":zero"), Code.CodeValueId("v:" .. name .. ":one")
    local i, acc, cond, item, other = Code.CodeValueId("v:" .. name .. ":i"), Code.CodeValueId("v:" .. name .. ":acc"), Code.CodeValueId("v:" .. name .. ":cond"), Code.CodeValueId("v:" .. name .. ":item"), Code.CodeValueId("v:" .. name .. ":other")
    local mapped, next_i, next_acc, out = Code.CodeValueId("v:" .. name .. ":mapped"), Code.CodeValueId("v:" .. name .. ":next_i"), Code.CodeValueId("v:" .. name .. ":next_acc"), Code.CodeValueId("v:" .. name .. ":out")
    local entry_id, header_id, body_id, exit_id = Code.CodeBlockId("block:" .. name .. ":entry"), Code.CodeBlockId("block:" .. name .. ":header"), Code.CodeBlockId("block:" .. name .. ":body"), Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id, func_id = Code.CodeSigId("sig:" .. name), Code.CodeFuncId("fn:" .. name)
    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero, zero })), origin)
    local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin), Code.CodeParam(acc, "acc", i32, origin) }, {
        inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
    local body_insts = { inst(name .. ":load", Code.CodeInstLoad(item, place(xs.value, i, i32), access(Code.CodeMemoryRead, i32))) }
    if kind == "count" then
        body_insts[#body_insts + 1] = inst(name .. ":map", Code.CodeInstCompare(mapped, Core.CmpGt, i32, item, zero))
    elseif kind == "unary_reduce_n" then
        body_insts[#body_insts + 1] = inst(name .. ":map", Code.CodeInstUnary(mapped, Core.UnaryNeg, i32, item))
    elseif kind == "binary_reduce_n" then
        body_insts[#body_insts + 1] = inst(name .. ":load_rhs", Code.CodeInstLoad(other, place(ys.value, i, i32), access(Code.CodeMemoryRead, i32)))
        body_insts[#body_insts + 1] = inst(name .. ":map", Code.CodeInstBinary(mapped, Core.BinAdd, i32, sem, item, other))
    end
    body_insts[#body_insts + 1] = inst(name .. ":reduce", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, mapped))
    body_insts[#body_insts + 1] = inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))
    local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(name .. ":body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term(name .. ":exit", Code.CodeTermReturn({ out })), origin)
    local params = kind == "binary_reduce_n" and { xs, ys, n } or { xs, n }
    local sig_params = kind == "binary_reduce_n" and { ptr(i32), ptr(i32), i32 } or { ptr(i32), i32 }
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, params, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, sig_params, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    local facts = {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    }
    if kind == "binary_reduce_n" then
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(ys.value, n.value), origin)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(xs.value, ys.value), origin)
    end
    return module, Code.CodeContractFactSet(module.id, facts), name
end

local n = 5
local xs = ffi.new("int32_t[5]", { 1, -2, 5, 0, 3 })
local ys = ffi.new("int32_t[5]", { 10, 20, 30, 40, 50 })
local idx = ffi.new("int32_t[5]", { 2, 0, 4, 1, 3 })
local out_i32 = ffi.new("int32_t[5]")
local out_bool = ffi.new("uint8_t[5]")
local out_f64 = ffi.new("double[5]")

do
    local module, contracts, name = store_case("cast", f64)
    compile_module(module, contracts, { name = name, store = true, basis = Stencil.StencilStore })(out_f64, xs, ys, idx, n)
    assert(out_f64[0] == 1 and out_f64[1] == -2 and out_f64[2] == 5 and out_f64[3] == 0 and out_f64[4] == 3, "lower cast")
end

do
    local module, contracts, name = store_case("compare", bool8)
    compile_module(module, contracts, { name = name, store = true, basis = Stencil.StencilStore })(out_bool, xs, ys, idx, n)
    assert(out_bool[0] == 1 and out_bool[1] == 0 and out_bool[2] == 1 and out_bool[3] == 0 and out_bool[4] == 1, "lower compare")
end

do
    local module, contracts, name = store_case("compare", bool8)
    local loop_id = Graph.GraphLoopId("loop:" .. name .. ":block_" .. name .. "_header:block_" .. name .. "_body")
    local domain = Flow.FlowDomainLoop(loop_id)
    local zero = Code.CodeValueId("v:" .. name .. ":zero")
    local one = Code.CodeValueId("v:" .. name .. ":one")
    local n_value = module.funcs[1].params[5].value
    local graph = CodeGraph.graph(module)
    local base_flow = CodeFlowFacts.facts(module, graph)
    local shape_fact = Flow.FlowDomainShapeFact(
        domain,
        Flow.FlowDomainShapeRangeND({
            Flow.FlowDomainAxis(Code.CodeTyIndex, Value.ValueExprValue(zero), Value.ValueExprValue(n_value), 1, Flow.FlowDomainForward),
            Flow.FlowDomainAxis(Code.CodeTyIndex, Value.ValueExprValue(zero), Value.ValueExprValue(one), 1, Flow.FlowDomainForward),
        }),
        { Flow.FlowProofDomain(domain, "test frontend fact maps loop domain to RangeND producer") },
        Flow.FlowFactFrontendFact("test domain shape fact")
    )
    local flow = Flow.FlowFactSet(
        base_flow.module,
        base_flow.domains,
        base_flow.edges,
        base_flow.loops,
        base_flow.ranges,
        { shape_fact },
        base_flow.domain_intents or {},
        base_flow.rejects
    )
    compile_module(module, contracts, {
        name = name,
        store = true,
        basis = Stencil.StencilStore,
        producer = Stencil.StencilProduceRangeND,
        flow = flow,
    })(out_bool, xs, ys, idx, n)
    assert(out_bool[0] == 1 and out_bool[1] == 0 and out_bool[2] == 1 and out_bool[3] == 0 and out_bool[4] == 1, "lower compare with RangeND producer fact")
end

do
    local module, contracts, name = store_case("zip_compare", bool8)
    compile_module(module, contracts, { name = name, store = true, basis = Stencil.StencilStore })(out_bool, xs, ys, idx, n)
    assert(out_bool[0] == 1 and out_bool[1] == 1 and out_bool[2] == 1 and out_bool[3] == 1 and out_bool[4] == 1, "lower zip compare")
end

do
    local module, contracts, name = store_case("gather", i32)
    compile_module(module, contracts, { name = name, store = true, basis = Stencil.StencilStore })(out_i32, xs, ys, idx, n)
    assert(out_i32[0] == 5 and out_i32[1] == 1 and out_i32[2] == 3 and out_i32[3] == -2 and out_i32[4] == 0, "lower gather")
end

do
    local module, contracts, name = store_case("scatter", i32)
    for i = 0, n - 1 do out_i32[i] = 0 end
    compile_module(module, contracts, { name = name, store = true, basis = Stencil.StencilStore })(out_i32, xs, ys, idx, n)
    assert(out_i32[0] == -2 and out_i32[1] == 0 and out_i32[2] == 1 and out_i32[3] == 3 and out_i32[4] == 5, "lower scatter")
end

do
    local module, contracts, name = store_case("in_place_map", i32)
    local inplace = ffi.new("int32_t[5]", { 1, -2, 5, 0, 3 })
    compile_module(module, contracts, { name = name, store = true, basis = Stencil.StencilStore })(inplace, n)
    assert(inplace[0] == -1 and inplace[1] == 2 and inplace[2] == -5 and inplace[3] == 0 and inplace[4] == -3, "lower in-place map")
end

do
    local module, contracts, name = reduction_case("count")
    assert(compile_module(module, contracts, { name = name, reduce = true, basis = Stencil.StencilReduce })(xs, n) == 3, "lower count")
end

do
    local module, contracts, name = reduction_case("unary_reduce_n")
    assert(compile_module(module, contracts, { name = name, reduce = true, basis = Stencil.StencilReduce })(xs, n) == -7, "lower unary reduce_n")
end

do
    local module, contracts, name = reduction_case("binary_reduce_n")
    assert(compile_module(module, contracts, { name = name, reduce = true, basis = Stencil.StencilReduce })(xs, ys, n) == 157, "lower binary reduce_n")
end

io.write("lalin luajit_lower_stencil_extended ok\n")
