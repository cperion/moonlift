package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local LJ = T.MoonLuaJIT
local Stencil = T.MoonStencil

local Lower = require("moonlift.luajit_lower")(T)
local Emit = require("moonlift.luajit_emit")(T)
local StencilC = require("moonlift.stencil_c")(T)

local origin = Code.CodeOriginGenerated("test_luajit_lower_stencil_store")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local read_access = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, false, nil)
local write_access = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end

local function index_place(base, i)
    return Code.CodePlaceIndex(Code.CodePlaceDeref(base, i32, 4), i, i32, 4)
end

local function build_case(case)
    local dst = param("dst", ptr_i32)
    local n = param("n", i32)
    local value = case.kind == "fill" and param("value", i32) or nil
    local src = (case.kind == "copy" or case.kind == "map") and param("src", ptr_i32) or nil
    local lhs = case.kind == "zip" and param("lhs", ptr_i32) or nil
    local rhs = case.kind == "zip" and param("rhs", ptr_i32) or nil
    local params = { dst }
    if src ~= nil then params[#params + 1] = src end
    if lhs ~= nil then params[#params + 1] = lhs end
    if rhs ~= nil then params[#params + 1] = rhs end
    params[#params + 1] = n
    if value ~= nil then params[#params + 1] = value end

    local zero = Code.CodeValueId("v:" .. case.name .. ":zero")
    local one = Code.CodeValueId("v:" .. case.name .. ":one")
    local i = Code.CodeValueId("v:" .. case.name .. ":i")
    local cond = Code.CodeValueId("v:" .. case.name .. ":cond")
    local next_i = Code.CodeValueId("v:" .. case.name .. ":next_i")
    local item = Code.CodeValueId("v:" .. case.name .. ":item")
    local item_l = Code.CodeValueId("v:" .. case.name .. ":lhs_item")
    local item_r = Code.CodeValueId("v:" .. case.name .. ":rhs_item")
    local mapped = Code.CodeValueId("v:" .. case.name .. ":mapped")
    local summed = Code.CodeValueId("v:" .. case.name .. ":summed")
    local entry_id = Code.CodeBlockId("block:" .. case.name .. ":entry")
    local header_id = Code.CodeBlockId("block:" .. case.name .. ":header")
    local body_id = Code.CodeBlockId("block:" .. case.name .. ":body")
    local exit_id = Code.CodeBlockId("block:" .. case.name .. ":exit")
    local sig_id = Code.CodeSigId("sig:" .. case.name)
    local func_id = Code.CodeFuncId("fn:" .. case.name)

    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(case.name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(case.name .. ":one", Code.CodeInstConst(one, Code.CodeConstLiteral(i32, Core.LitInt("1")))),
    }, term(case.name .. ":entry", Code.CodeTermJump(header_id, { zero })), origin)

    local header = Code.CodeBlock(header_id, "header", {
        Code.CodeParam(i, "i", i32, origin),
    }, {
        inst(case.name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    }, term(case.name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, {})), origin)

    local body_insts = {}
    local store_value
    if case.kind == "fill" then
        store_value = value.value
    elseif case.kind == "copy" then
        body_insts[#body_insts + 1] = inst(case.name .. ":load", Code.CodeInstLoad(item, index_place(src.value, i), read_access))
        store_value = item
    elseif case.kind == "map" then
        body_insts[#body_insts + 1] = inst(case.name .. ":load", Code.CodeInstLoad(item, index_place(src.value, i), read_access))
        body_insts[#body_insts + 1] = inst(case.name .. ":neg", Code.CodeInstUnary(mapped, Core.UnaryNeg, i32, item))
        store_value = mapped
    elseif case.kind == "zip" then
        body_insts[#body_insts + 1] = inst(case.name .. ":load_l", Code.CodeInstLoad(item_l, index_place(lhs.value, i), read_access))
        body_insts[#body_insts + 1] = inst(case.name .. ":load_r", Code.CodeInstLoad(item_r, index_place(rhs.value, i), read_access))
        body_insts[#body_insts + 1] = inst(case.name .. ":add", Code.CodeInstBinary(summed, Core.BinAdd, i32, sem, item_l, item_r))
        store_value = summed
    else
        error("unknown case kind " .. tostring(case.kind))
    end
    body_insts[#body_insts + 1] = inst(case.name .. ":store", Code.CodeInstStore(index_place(dst.value, i), store_value, write_access))
    body_insts[#body_insts + 1] = inst(case.name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, one))

    local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(case.name .. ":body", Code.CodeTermJump(header_id, { next_i })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", {}, {}, term(case.name .. ":exit", Code.CodeTermReturn({})), origin)
    local func = Code.CodeFunc(func_id, case.name, Code.CodeLinkageExport, sig_id, params, {}, entry_id, { entry, header, body, exit }, origin)
    local sig_params = {}
    for i = 1, #params do sig_params[i] = params[i].ty end
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. case.name), { Code.CodeSig(sig_id, sig_params, {}) }, {}, {}, {}, {}, { func }, origin)

    local facts = {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(dst.value, n.value), origin),
        Code.CodeFuncContractFact(func_id, Code.CodeContractWriteonly(dst.value), origin),
    }
    local function add_read_ptr(p)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(p.value, n.value), origin)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractReadonly(p.value), origin)
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(dst.value, p.value), origin)
    end
    if src ~= nil then add_read_ptr(src) end
    if lhs ~= nil then add_read_ptr(lhs) end
    if rhs ~= nil then add_read_ptr(rhs) end
    if lhs ~= nil and rhs ~= nil then
        facts[#facts + 1] = Code.CodeFuncContractFact(func_id, Code.CodeContractDisjoint(lhs.value, rhs.value), origin)
    end

    return module, Code.CodeContractFactSet(module.id, facts)
end

local function select_artifact(func, vocab, op, plan, info)
    if vocab == Stencil.StencilCopy then return StencilC.copy_array_artifact(info) end
    if vocab == Stencil.StencilFill then return StencilC.fill_array_artifact(info) end
    if vocab == Stencil.StencilMap then return StencilC.map_array_artifact(op, info) end
    if vocab == Stencil.StencilZipMap then return StencilC.zip_map_array_artifact(op, info) end
    error("unexpected store stencil vocab " .. tostring(vocab))
end

local function compile_case(case)
    local module, contracts = build_case(case)
    local rejects, artifacts = {}, {}
    local lj_module = Lower.lower_module(module, {
        contracts = contracts,
        collect_rejects = rejects,
        stencil_store_artifact_for = function(func, vocab, op, plan, info)
            local artifact = select_artifact(func, vocab, op, plan, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end,
        stencil_skeleton_artifact_for = function(func, vocab, op, reduction, plan, info)
            local artifact = select_artifact(func, vocab, op, plan, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end,
    })
    assert(#rejects == 0, case.name .. " rejected: " .. tostring(rejects[1] and rejects[1].reason))
    assert(#artifacts == 1, case.name .. " should select one store stencil artifact")
    assert(pvm.classof(lj_module.funcs[1].body) == LJ.LJBodyMachine, case.name .. " should lower to machine body")
    assert(pvm.classof(lj_module.funcs[1].machines[1].kind) == LJ.LJMachineStencilEffect, case.name .. " should lower to stencil effect")

    local build, build_err, csrc = StencilC.compile_artifacts(artifacts, { stem = "test_luajit_lower_stencil_store_" .. case.name })
    assert(build ~= nil, tostring(build_err) .. "\n" .. tostring(csrc))
    local compiled, err, src = Emit.compile_module(lj_module, {
        chunk_name = "test_luajit_lower_stencil_store_" .. case.name,
        stencil_symbols = build.symbols,
    })
    assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))
    return compiled[case.name]
end

local n = 6
local xs = ffi.new("int32_t[?]", n)
local ys = ffi.new("int32_t[?]", n)
local out = ffi.new("int32_t[?]", n)
for i = 0, n - 1 do
    xs[i] = i * 3 - 4
    ys[i] = 20 - i
    out[i] = -999
end

compile_case({ name = "store_copy_i32", kind = "copy" })(out, xs, n)
for i = 0, n - 1 do assert(out[i] == xs[i], "copy mismatch at " .. tostring(i)) end

compile_case({ name = "store_fill_i32", kind = "fill" })(out, n, 77)
for i = 0, n - 1 do assert(out[i] == 77, "fill mismatch at " .. tostring(i)) end

compile_case({ name = "store_map_neg_i32", kind = "map" })(out, xs, n)
for i = 0, n - 1 do assert(out[i] == -xs[i], "map mismatch at " .. tostring(i)) end

compile_case({ name = "store_zip_add_i32", kind = "zip" })(out, xs, ys, n)
for i = 0, n - 1 do assert(out[i] == xs[i] + ys[i], "zip mismatch at " .. tostring(i)) end

io.write("moonlift luajit_lower_stencil_store ok\n")
