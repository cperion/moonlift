package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")

local T = pvm.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Kernel = T.LalinKernel
local LJ = T.LalinLuaJIT
local Stencil = T.LalinStencil
local Value = T.LalinValue

local Lower = require("lalin.luajit_lower")(T)
local Emit = require("lalin.luajit_emit")(T)
local StencilArtifactPlan = require("lalin.stencil_artifact_plan")(T)
local StencilBinary = require("tests.code_ir.stencil_binary_helper")

local origin = Code.CodeOriginGenerated("test_luajit_lower_stencil_skeletons")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_i32 = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_i32 = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end
local function place(base, index) return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), index, i32, 4) end
local function iconst(raw) return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw)))) end

local function build_loop_case(name, opts)
    local dst = opts.dst and param(name .. "_dst", Code.CodeTyDataPtr(i32)) or nil
    local src = param(name .. "_src", Code.CodeTyDataPtr(i32))
    local n = param(name .. "_n", i32)
    local zero = Code.CodeValueId("v:" .. name .. ":zero")
    local one = Code.CodeValueId("v:" .. name .. ":one")
    local i = Code.CodeValueId("v:" .. name .. ":i")
    local acc = Code.CodeValueId("v:" .. name .. ":acc")
    local cond = Code.CodeValueId("v:" .. name .. ":cond")
    local item = Code.CodeValueId("v:" .. name .. ":item")
    local next_i = Code.CodeValueId("v:" .. name .. ":next_i")
    local next_acc = Code.CodeValueId("v:" .. name .. ":next_acc")
    local out = Code.CodeValueId("v:" .. name .. ":out")
    local entry_id = Code.CodeBlockId("block:" .. name .. ":entry")
    local header_id = Code.CodeBlockId("block:" .. name .. ":header")
    local body_id = Code.CodeBlockId("block:" .. name .. ":body")
    local exit_id = Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id = Code.CodeSigId("sig:" .. name)
    local func_id = Code.CodeFuncId("fn:" .. name)
    local entry_args = opts.reduce and { zero, zero } or { zero }
    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(name .. ":entry", Code.CodeTermJump(header_id, entry_args)), origin)
    local header_params = { Code.CodeParam(i, "i", i32, origin) }
    if opts.reduce then header_params[#header_params + 1] = Code.CodeParam(acc, "acc", i32, origin) end
    local header = Code.CodeBlock(header_id, "header", header_params, {
        inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, opts.reduce and { acc } or {})), origin)
    local body_insts = {
        inst(name .. ":load", Code.CodeInstLoad(item, place(src.value, i), read_i32)),
    }
    local latch_args
    if opts.reduce then
        body_insts[#body_insts + 1] = inst(name .. ":reduce", Code.CodeInstBinary(next_acc, Core.BinAdd, i32, sem, acc, item))
        if opts.dst then body_insts[#body_insts + 1] = inst(name .. ":store", Code.CodeInstStore(place(dst.value, i), next_acc, write_i32)) end
        body_insts[#body_insts + 1] = inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))
        latch_args = { next_i, next_acc }
    else
        if opts.dst then body_insts[#body_insts + 1] = inst(name .. ":store", Code.CodeInstStore(place(dst.value, i), item, write_i32)) end
        body_insts[#body_insts + 1] = inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))
        latch_args = { next_i }
    end
    local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(name .. ":body", Code.CodeTermJump(header_id, latch_args)), origin)
    local exit_params = opts.reduce and { Code.CodeParam(out, "out", i32, origin) } or {}
    local ret_values = opts.returns_i32 and { opts.reduce and out or zero } or {}
    local exit = Code.CodeBlock(exit_id, "exit", exit_params, {}, term(name .. ":exit", Code.CodeTermReturn(ret_values)), origin)
    local params = opts.dst and { dst, src, n } or { src, n }
    local sig_params = opts.dst and { Code.CodeTyDataPtr(i32), Code.CodeTyDataPtr(i32), i32 } or { Code.CodeTyDataPtr(i32), i32 }
    local sig_results = opts.returns_i32 and { i32 } or {}
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, params, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, sig_params, sig_results) }, {}, {}, {}, {}, { func }, origin)
    local facts = {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(src.value, n.value), origin),
    }
    if dst ~= nil then
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, n.value), origin)
        if not opts.allow_overlap then
            facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, src.value), origin)
        end
    end
    return module, Code.CodeContractFactSet(module.id, facts), name
end

local function build_find_case(name)
    local src = param(name .. "_src", Code.CodeTyDataPtr(i32))
    local n = param(name .. "_n", i32)
    local zero = Code.CodeValueId("v:" .. name .. ":zero")
    local one = Code.CodeValueId("v:" .. name .. ":one")
    local minus_one = Code.CodeValueId("v:" .. name .. ":minus_one")
    local i = Code.CodeValueId("v:" .. name .. ":i")
    local cond = Code.CodeValueId("v:" .. name .. ":cond")
    local item = Code.CodeValueId("v:" .. name .. ":item")
    local predv = Code.CodeValueId("v:" .. name .. ":pred")
    local next_i = Code.CodeValueId("v:" .. name .. ":next_i")
    local out = Code.CodeValueId("v:" .. name .. ":out")
    local entry_id = Code.CodeBlockId("block:" .. name .. ":entry")
    local header_id = Code.CodeBlockId("block:" .. name .. ":header")
    local body_id = Code.CodeBlockId("block:" .. name .. ":body")
    local latch_id = Code.CodeBlockId("block:" .. name .. ":latch")
    local exit_id = Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id = Code.CodeSigId("sig:" .. name)
    local func_id = Code.CodeFuncId("fn:" .. name)
    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
        inst(name .. ":minus_one", Code.CodeInstConst(minus_one, Code.CodeConstLiteral(i32, Core.LitInt("-1")))),
    }, term(name .. ":entry", Code.CodeTermJump(header_id, { zero })), origin)
    local header = Code.CodeBlock(header_id, "header", { Code.CodeParam(i, "i", i32, origin) }, {
        inst(name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    }, term(name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { minus_one })), origin)
    local body = Code.CodeBlock(body_id, "body", {}, {
        inst(name .. ":load", Code.CodeInstLoad(item, place(src.value, i), read_i32)),
        inst(name .. ":pred", Code.CodeInstCompare(predv, Core.CmpGt, i32, item, zero)),
    }, term(name .. ":body", Code.CodeTermBranch(predv, exit_id, { i }, latch_id, {})), origin)
    local latch = Code.CodeBlock(latch_id, "latch", {}, {
        inst(name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one)),
    }, term(name .. ":latch", Code.CodeTermJump(header_id, { next_i })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", i32, origin) }, {}, term(name .. ":exit", Code.CodeTermReturn({ out })), origin)
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, { src, n }, {}, entry_id, { entry, header, body, latch, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, { Code.CodeTyDataPtr(i32), i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    local facts = { Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(src.value, n.value), origin) }
    return module, Code.CodeContractFactSet(module.id, facts), name
end

local function build_partition_case(name)
    local dst = param(name .. "_dst", Code.CodeTyDataPtr(i32))
    local src = param(name .. "_src", Code.CodeTyDataPtr(i32))
    local n = param(name .. "_n", i32)
    local zero = Code.CodeValueId("v:" .. name .. ":zero")
    local one = Code.CodeValueId("v:" .. name .. ":one")
    local i = Code.CodeValueId("v:" .. name .. ":i")
    local out1 = Code.CodeValueId("v:" .. name .. ":out1")
    local j = Code.CodeValueId("v:" .. name .. ":j")
    local out2 = Code.CodeValueId("v:" .. name .. ":out2")
    local cond1 = Code.CodeValueId("v:" .. name .. ":cond1")
    local cond2 = Code.CodeValueId("v:" .. name .. ":cond2")
    local item1 = Code.CodeValueId("v:" .. name .. ":item1")
    local item2 = Code.CodeValueId("v:" .. name .. ":item2")
    local pred1 = Code.CodeValueId("v:" .. name .. ":pred1")
    local pred2 = Code.CodeValueId("v:" .. name .. ":pred2")
    local next_i_a = Code.CodeValueId("v:" .. name .. ":next_i_a")
    local next_i_b = Code.CodeValueId("v:" .. name .. ":next_i_b")
    local next_j_a = Code.CodeValueId("v:" .. name .. ":next_j_a")
    local next_j_b = Code.CodeValueId("v:" .. name .. ":next_j_b")
    local next_out1 = Code.CodeValueId("v:" .. name .. ":next_out1")
    local next_out2 = Code.CodeValueId("v:" .. name .. ":next_out2")
    local retv = Code.CodeValueId("v:" .. name .. ":ret")
    local entry_id = Code.CodeBlockId("block:" .. name .. ":entry")
    local h1_id = Code.CodeBlockId("block:" .. name .. ":h1")
    local b1_id = Code.CodeBlockId("block:" .. name .. ":b1")
    local s1_id = Code.CodeBlockId("block:" .. name .. ":s1")
    local l1_id = Code.CodeBlockId("block:" .. name .. ":l1")
    local h2_id = Code.CodeBlockId("block:" .. name .. ":h2")
    local b2_id = Code.CodeBlockId("block:" .. name .. ":b2")
    local s2_id = Code.CodeBlockId("block:" .. name .. ":s2")
    local l2_id = Code.CodeBlockId("block:" .. name .. ":l2")
    local exit_id = Code.CodeBlockId("block:" .. name .. ":exit")
    local sig_id = Code.CodeSigId("sig:" .. name)
    local func_id = Code.CodeFuncId("fn:" .. name)
    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(name .. ":entry", Code.CodeTermJump(h1_id, { zero, zero })), origin)
    local h1 = Code.CodeBlock(h1_id, "h1", { Code.CodeParam(i, "i", i32, origin), Code.CodeParam(out1, "out1", i32, origin) }, {
        inst(name .. ":cond1", Code.CodeInstCompare(cond1, Core.CmpLt, i32, i, n.value)),
    }, term(name .. ":h1", Code.CodeTermBranch(cond1, b1_id, {}, h2_id, { zero, out1 })), origin)
    local b1 = Code.CodeBlock(b1_id, "b1", {}, {
        inst(name .. ":load1", Code.CodeInstLoad(item1, place(src.value, i), read_i32)),
        inst(name .. ":pred1", Code.CodeInstCompare(pred1, Core.CmpGt, i32, item1, zero)),
    }, term(name .. ":b1", Code.CodeTermBranch(pred1, s1_id, {}, l1_id, {})), origin)
    local s1 = Code.CodeBlock(s1_id, "s1", {}, {
        inst(name .. ":store1", Code.CodeInstStore(place(dst.value, out1), item1, write_i32)),
        inst(name .. ":next_out1", Code.CodeInstBinary(next_out1, Core.BinAdd, i32, sem, out1, one)),
        inst(name .. ":next_i_a", Code.CodeInstBinary(next_i_a, Core.BinAdd, i32, sem, i, one)),
    }, term(name .. ":s1", Code.CodeTermJump(h1_id, { next_i_a, next_out1 })), origin)
    local l1 = Code.CodeBlock(l1_id, "l1", {}, {
        inst(name .. ":next_i_b", Code.CodeInstBinary(next_i_b, Core.BinAdd, i32, sem, i, one)),
    }, term(name .. ":l1", Code.CodeTermJump(h1_id, { next_i_b, out1 })), origin)
    local h2 = Code.CodeBlock(h2_id, "h2", { Code.CodeParam(j, "j", i32, origin), Code.CodeParam(out2, "out2", i32, origin) }, {
        inst(name .. ":cond2", Code.CodeInstCompare(cond2, Core.CmpLt, i32, j, n.value)),
    }, term(name .. ":h2", Code.CodeTermBranch(cond2, b2_id, {}, exit_id, { out2 })), origin)
    local b2 = Code.CodeBlock(b2_id, "b2", {}, {
        inst(name .. ":load2", Code.CodeInstLoad(item2, place(src.value, j), read_i32)),
        inst(name .. ":pred2", Code.CodeInstCompare(pred2, Core.CmpGt, i32, item2, zero)),
    }, term(name .. ":b2", Code.CodeTermBranch(pred2, l2_id, {}, s2_id, {})), origin)
    local s2 = Code.CodeBlock(s2_id, "s2", {}, {
        inst(name .. ":store2", Code.CodeInstStore(place(dst.value, out2), item2, write_i32)),
        inst(name .. ":next_out2", Code.CodeInstBinary(next_out2, Core.BinAdd, i32, sem, out2, one)),
        inst(name .. ":next_j_a", Code.CodeInstBinary(next_j_a, Core.BinAdd, i32, sem, j, one)),
    }, term(name .. ":s2", Code.CodeTermJump(h2_id, { next_j_a, next_out2 })), origin)
    local l2 = Code.CodeBlock(l2_id, "l2", {}, {
        inst(name .. ":next_j_b", Code.CodeInstBinary(next_j_b, Core.BinAdd, i32, sem, j, one)),
    }, term(name .. ":l2", Code.CodeTermJump(h2_id, { next_j_b, out2 })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(retv, "ret", i32, origin) }, {}, term(name .. ":exit", Code.CodeTermReturn({ retv })), origin)
    local func = Code.CodeFunc(func_id, name, Code.CodeLinkageExport, sig_id, { dst, src, n }, {}, entry_id, { entry, h1, b1, s1, l1, h2, b2, s2, l2, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. name), { Code.CodeSig(sig_id, { Code.CodeTyDataPtr(i32), Code.CodeTyDataPtr(i32), i32 }, { i32 }) }, {}, {}, {}, {}, { func }, origin)
    local facts = {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, n.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(src.value, n.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, src.value), origin),
    }
    return module, Code.CodeContractFactSet(module.id, facts), name
end

local function planned_kernel(module, contracts, mutate)
    local graph, flow, value, mem, effect, kernel = Lower.build_kernel(module, { contracts = contracts })
    local base
    for _, plan in ipairs(kernel.plans or {}) do
        if pvm.classof(plan) == Kernel.KernelPlanned then base = plan; break end
    end
    assert(base ~= nil, "expected planned kernel")
    local body = base.body
    local effects, result = mutate(body)
    local custom_body = Kernel.KernelBody(body.domain, body.lanes, body.bindings, effects, result, body.equivalence)
    local custom_plan = Kernel.KernelPlanned(Kernel.KernelId(base.id.text .. ":skeleton"), base.subject, custom_body)
    return graph, flow, value, mem, effect, Kernel.KernelModulePlan(module.id, flow, value, mem, effect, { custom_plan })
end

local function first_effect(body, cls)
    for _, effect in ipairs(body.effects or {}) do if pvm.classof(effect) == cls then return effect end end
    return nil
end

local function first_load_expr(body)
    for _, binding in ipairs(body.bindings or {}) do
        if pvm.classof(binding.expr) == Kernel.KernelExprLaneLoad then return binding.expr end
    end
    error("missing load expression")
end

local function provider(func, vocab, op, reduction, plan, info)
    if vocab == Stencil.StencilScan then return StencilArtifactPlan.scan_array_artifact(reduction, plan, info) end
    if vocab == Stencil.StencilFind then return StencilArtifactPlan.find_array_artifact(op, info) end
    if vocab == Stencil.StencilPartition then return StencilArtifactPlan.partition_array_artifact(op, info) end
    if vocab == Stencil.StencilCopy then return StencilArtifactPlan.copy_array_artifact(info) end
    error("unexpected skeleton vocab " .. tostring(vocab))
end

local function compile_with_kernel(module, graph, flow, value, mem, effect, kernel, name)
    local artifacts = {}
    local lj_module, facts = Lower.lower_module(module, {
        graph = graph,
        flow = flow,
        value = value,
        mem = mem,
        effect = effect,
        kernel = kernel,
        stencil_skeleton_artifact_for = function(func, vocab, op, reduction, plan, info)
            local artifact = provider(func, vocab, op, reduction, plan, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end,
    })
    assert(#artifacts == 1, name .. " should select one skeleton artifact")
    assert(pvm.classof(lj_module.funcs[1].body) == LJ.LJBodyMachine, name .. " should lower to machine body")
    local build, build_err, csrc = StencilBinary.compile(T, artifacts, { stem = "test_luajit_lower_stencil_skeletons_" .. name })
    assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))
    local compiled, err, src = Emit.compile_module(lj_module, {
        chunk_name = "test_luajit_lower_stencil_skeletons_" .. name,
        stencil_symbols = build.symbols,
    })
    assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))
    return compiled[name]
end

local function compile_auto_skeleton(module, contracts, name)
    local artifacts, rejects = {}, {}
    local lj_module, facts = Lower.lower_module(module, {
        contracts = contracts,
        collect_rejects = rejects,
        stencil_skeleton_artifact_for = function(func, vocab, op, reduction, plan, info)
            local artifact = provider(func, vocab, op, reduction, plan, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end,
    })
    local graph_loops = 0
    local graph_edges = 0
    local graph_exits = "none"
    for _, fg in ipairs(facts.graph.funcs or {}) do
        graph_loops = graph_loops + #(fg.loops or {})
        graph_edges = graph_edges + #(fg.edges or {})
        if fg.loops and fg.loops[1] then graph_exits = tostring(#(fg.loops[1].exits or {})) end
    end
    local planned_result = "none:funcs=" .. tostring(#(facts.graph.funcs or {})) .. ":plans=" .. tostring(#(facts.kernel.plans or {})) .. ":graph_edges=" .. tostring(graph_edges) .. ":graph_loops=" .. tostring(graph_loops) .. ":graph_exits=" .. graph_exits .. ":flow_loops=" .. tostring(#(facts.flow.loops or {}))
    local plan_info = planned_result
    for _, plan in ipairs(facts.kernel.plans or {}) do
        if pvm.classof(plan) == Kernel.KernelPlanned then planned_result = tostring(pvm.classof(plan.body.result)) .. ":" .. plan_info end
        if pvm.classof(plan) == Kernel.KernelNoPlan and planned_result == "none" and plan.rejects and plan.rejects[1] then
            planned_result = "no-plan:" .. tostring(plan.rejects[1].reason)
        end
    end
    assert(#artifacts == 1, name .. " should select one skeleton artifact: " .. tostring(rejects[1] and rejects[1].reason) .. " planned=" .. planned_result)
    assert(pvm.classof(lj_module.funcs[1].body) == LJ.LJBodyMachine, name .. " should lower to machine body")
    local build, build_err, csrc = StencilBinary.compile(T, artifacts, { stem = "test_luajit_lower_stencil_skeletons_" .. name })
    assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))
    local compiled, err, src = Emit.compile_module(lj_module, {
        chunk_name = "test_luajit_lower_stencil_skeletons_" .. name,
        stencil_symbols = build.symbols,
    })
    assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))
    return compiled[name]
end

local n = 5
local xs = ffi.new("int32_t[5]", { 1, -2, 5, 0, 3 })
local out = ffi.new("int32_t[5]")
local pred = Stencil.StencilPredGtConst(iconst(0))

do
    local module, contracts, name = build_loop_case("skeleton_scan", { dst = true, reduce = true, returns_i32 = true })
    local graph, flow, value, mem, effect, kernel = planned_kernel(module, contracts, function(body)
        assert(first_effect(body, Kernel.KernelEffectScan), "planner should infer scan effect")
        assert(first_effect(body, Kernel.KernelEffectFold), "scan still carries fold effect")
        assert(pvm.classof(body.result) == Kernel.KernelResultReduction, "scan should keep reduction result")
        return body.effects, body.result
    end)
    local fn = compile_with_kernel(module, graph, flow, value, mem, effect, kernel, name)
    assert(fn(out, xs, n) == 7, "scan final")
    assert(out[0] == 1 and out[1] == -1 and out[2] == 4 and out[3] == 4 and out[4] == 7, "scan output")
end

do
    local module, contracts, name = build_loop_case("skeleton_find", { reduce = false, returns_i32 = true })
    local graph, flow, value, mem, effect, kernel = planned_kernel(module, contracts, function(body)
        return {}, Kernel.KernelResultFind(first_load_expr(body), pred, iconst(-1))
    end)
    local fn = compile_with_kernel(module, graph, flow, value, mem, effect, kernel, name)
    assert(fn(xs, n) == 0, "find result")
end

do
    local module, contracts, name = build_find_case("skeleton_find_inferred")
    local fn = compile_auto_skeleton(module, contracts, name)
    assert(fn(xs, n) == 0, "inferred find result")
end

do
    local module, contracts, name = build_loop_case("skeleton_partition", { dst = true, reduce = false, returns_i32 = true })
    local graph, flow, value, mem, effect, kernel = planned_kernel(module, contracts, function(body)
        local copy = first_effect(body, Kernel.KernelEffectCopy)
        local store = first_effect(body, Kernel.KernelEffectStore)
        local dst = copy and copy.dst or assert(store, "partition needs store or inferred copy").dst
        local src = copy and copy.src or store.value
        return {
            Kernel.KernelEffectPartition(dst, src, pred, Stencil.StencilPartitionStable),
        }, Kernel.KernelResultValue(Kernel.KernelExprAlgebra(iconst(0)))
    end)
    local fn = compile_with_kernel(module, graph, flow, value, mem, effect, kernel, name)
    assert(fn(out, xs, n) == 3, "partition split")
    assert(out[0] == 1 and out[1] == 5 and out[2] == 3 and out[3] == -2 and out[4] == 0, "partition output")
end

do
    local module, contracts, name = build_partition_case("skeleton_partition_inferred")
    local fn = compile_auto_skeleton(module, contracts, name)
    assert(fn(out, xs, n) == 3, "inferred partition split")
    assert(out[0] == 1 and out[1] == 5 and out[2] == 3 and out[3] == -2 and out[4] == 0, "inferred partition output")
end

do
    local module, contracts, name = build_loop_case("skeleton_copy_memmove", { dst = true, reduce = false, returns_i32 = false })
    local graph, flow, value, mem, effect, kernel = planned_kernel(module, contracts, function(body)
        assert(first_effect(body, Kernel.KernelEffectCopy), "planner should infer copy effect")
        assert(body.result == Kernel.KernelResultVoid, "copy should have void result, got " .. tostring(pvm.classof(body.result)))
        return body.effects, body.result
    end)
    local fn = compile_with_kernel(module, graph, flow, value, mem, effect, kernel, name)
    fn(out, xs, n)
    assert(out[0] == 1 and out[1] == -2 and out[2] == 5 and out[3] == 0 and out[4] == 3, "copy memmove output")
end

do
    local module, contracts, name = build_loop_case("skeleton_copy_overlap", { dst = true, reduce = false, returns_i32 = false, allow_overlap = true })
    local graph, flow, value, mem, effect, kernel = planned_kernel(module, contracts, function(body)
        local copy = assert(first_effect(body, Kernel.KernelEffectCopy), "planner should infer overlap-safe copy effect")
        assert(copy.semantics == Stencil.StencilCopyMemMove, "unproven copy overlap should select memmove semantics")
        assert(body.result == Kernel.KernelResultVoid, "overlap copy should have void result")
        return body.effects, body.result
    end)
    local fn = compile_with_kernel(module, graph, flow, value, mem, effect, kernel, name)
    fn(out, xs, n)
    assert(out[0] == 1 and out[1] == -2 and out[2] == 5 and out[3] == 0 and out[4] == 3, "overlap-copy output")
end

io.write("lalin luajit_lower_stencil_skeletons ok\n")
