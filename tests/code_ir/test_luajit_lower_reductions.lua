package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local LJ = T.MoonLuaJIT
local Stencil = T.MoonStencil
local Value = T.MoonValue

local Lower = require("moonlift.luajit_lower")(T)
local Emit = require("moonlift.luajit_emit")(T)
local StencilC = require("moonlift.stencil_c")(T)
local StencilBinary = require("tests.code_ir.stencil_binary_helper")

local origin = Code.CodeOriginGenerated("test_luajit_lower_reductions")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local i64 = Code.CodeTyInt(64, Code.CodeSigned)
local f64 = Code.CodeTyFloat(64)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)

local function param(name, ty) return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin) end
local function inst(id, kind) return Code.CodeInst(Code.CodeInstId("inst:" .. id), kind, origin) end
local function term(id, kind) return Code.CodeTerm(Code.CodeTermId("term:" .. id), kind, origin) end

local function mask(bits)
    if bits == 8 then return 0xff end
    if bits == 16 then return 0xffff end
    return nil
end

local function norm(bits, signed, x)
    x = bit.tobit(x)
    if bits == 8 or bits == 16 then
        local m = mask(bits)
        local sign = bits == 8 and 0x80 or 0x8000
        local span = bits == 8 and 0x100 or 0x10000
        x = bit.band(x, m)
        if signed and x >= sign then return x - span end
        return x
    end
    if signed then return x end
    if x < 0 then return x + 4294967296 end
    return x
end

local function mul32(a, b)
    local al, bl = bit.band(a, 0xffff), bit.band(b, 0xffff)
    local ah, bh = bit.rshift(a, 16), bit.rshift(b, 16)
    return bit.tobit(al * bl + bit.lshift(bit.band(ah * bl + al * bh, 0xffff), 16))
end

local function is_float_ty(ty)
    return pvm.classof(ty) == Code.CodeTyFloat
end

local function reduce_expect(case, values)
    if case.float then
        local acc = tonumber(case.init)
        for _, v in ipairs(values) do
            local item = tonumber(v)
            if case.reduction == Value.ReductionAdd then
                acc = acc + item
            elseif case.reduction == Value.ReductionMul then
                acc = acc * item
            elseif case.reduction == Value.ReductionMin then
                if item < acc then acc = item end
            elseif case.reduction == Value.ReductionMax then
                if item > acc then acc = item end
            end
        end
        return acc
    end
    local acc = norm(case.bits, case.signed, tonumber(case.init))
    for _, v in ipairs(values) do
        local item = norm(case.bits, case.signed, v)
        if case.reduction == Value.ReductionAdd then
            acc = norm(case.bits, case.signed, acc + item)
        elseif case.reduction == Value.ReductionMul then
            if case.bits == 32 then acc = norm(case.bits, case.signed, mul32(acc, item))
            else acc = norm(case.bits, case.signed, acc * item) end
        elseif case.reduction == Value.ReductionAnd then
            acc = norm(case.bits, case.signed, bit.band(acc, item))
        elseif case.reduction == Value.ReductionOr then
            acc = norm(case.bits, case.signed, bit.bor(acc, item))
        elseif case.reduction == Value.ReductionXor then
            acc = norm(case.bits, case.signed, bit.bxor(acc, item))
        elseif case.reduction == Value.ReductionMin then
            if item < acc then acc = item end
        elseif case.reduction == Value.ReductionMax then
            if item > acc then acc = item end
        end
    end
    return acc
end

local function literal_for(case, raw)
    if case.float then return Core.LitFloat(tostring(raw)) end
    return Core.LitInt(tostring(raw))
end

local function build_case(case)
    local ty = case.ty
    case.float = case.float or is_float_ty(ty)
    local ptr_ty = Code.CodeTyDataPtr(ty)
    local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, ty, math.max(1, case.bits / 8), Code.CodeMustNotTrap, false, nil)
    local xs = param("xs", ptr_ty)
    local n = param("n", i32)
    local zero = Code.CodeValueId("v:zero")
    local init = Code.CodeValueId("v:init")
    local step = Code.CodeValueId("v:step")
    local i = Code.CodeValueId("v:i")
    local acc = Code.CodeValueId("v:acc")
    local cond = Code.CodeValueId("v:cond")
    local item = Code.CodeValueId("v:item")
    local next_i = Code.CodeValueId("v:next_i")
    local next_acc = Code.CodeValueId("v:next_acc")
    local sel_cond = Code.CodeValueId("v:sel_cond")
    local out = Code.CodeValueId("v:out")
    local entry_id = Code.CodeBlockId("block:" .. case.name .. ":entry")
    local header_id = Code.CodeBlockId("block:" .. case.name .. ":header")
    local body_id = Code.CodeBlockId("block:" .. case.name .. ":body")
    local exit_id = Code.CodeBlockId("block:" .. case.name .. ":exit")
    local sig_id = Code.CodeSigId("sig:" .. case.name)
    local func_id = Code.CodeFuncId("fn:" .. case.name)

    local entry = Code.CodeBlock(entry_id, "entry", {}, {
        inst(case.name .. ":zero", Code.CodeInstConst(zero, Code.CodeConstLiteral(i32, Core.LitInt("0")))),
        inst(case.name .. ":init", Code.CodeInstConst(init, Code.CodeConstLiteral(ty, literal_for(case, case.init)))),
        inst(case.name .. ":step", Code.CodeInstConst(step, Code.CodeConstLiteral(i32, Core.LitInt(tostring(case.step or 1))))),
    }, term(case.name .. ":entry", Code.CodeTermJump(header_id, { zero, init })), origin)
    local header = Code.CodeBlock(header_id, "header", {
        Code.CodeParam(i, "i", i32, origin),
        Code.CodeParam(acc, "acc", ty, origin),
    }, {
        inst(case.name .. ":cond", Code.CodeInstCompare(cond, Core.CmpLt, i32, i, n.value)),
    }, term(case.name .. ":header", Code.CodeTermBranch(cond, body_id, {}, exit_id, { acc })), origin)
    local body_insts = {
        inst(case.name .. ":load", Code.CodeInstLoad(item, Code.CodePlaceIndex(Code.CodePlaceDeref(xs.value, ty, math.max(1, case.bits / 8)), i, i32, math.max(1, case.bits / 8)), access)),
    }
    if case.reduction == Value.ReductionMin or case.reduction == Value.ReductionMax then
        local cmp = case.reduction == Value.ReductionMin and Core.CmpLe or Core.CmpGe
        body_insts[#body_insts + 1] = inst(case.name .. ":sel_cond", Code.CodeInstCompare(sel_cond, cmp, ty, acc, item))
        body_insts[#body_insts + 1] = inst(case.name .. ":reduce", Code.CodeInstSelect(next_acc, ty, sel_cond, acc, item))
    else
        if case.float then
            body_insts[#body_insts + 1] = inst(case.name .. ":reduce", Code.CodeInstFloatBinary(next_acc, case.op, ty, Code.CodeFloatStrict, acc, item))
        else
            body_insts[#body_insts + 1] = inst(case.name .. ":reduce", Code.CodeInstBinary(next_acc, case.op, ty, sem, acc, item))
        end
    end
    body_insts[#body_insts + 1] = inst(case.name .. ":inc", Code.CodeInstBinary(next_i, Core.BinAdd, i32, sem, i, step))
    local body = Code.CodeBlock(body_id, "body", {}, body_insts, term(case.name .. ":body", Code.CodeTermJump(header_id, { next_i, next_acc })), origin)
    local exit = Code.CodeBlock(exit_id, "exit", { Code.CodeParam(out, "out", ty, origin) }, {}, term(case.name .. ":exit", Code.CodeTermReturn({ out })), origin)
    local func = Code.CodeFunc(func_id, case.name, Code.CodeLinkageExport, sig_id, { xs, n }, {}, entry_id, { entry, header, body, exit }, origin)
    local module = Code.CodeModule(Code.CodeModuleId("module:" .. case.name), { Code.CodeSig(sig_id, { ptr_ty, i32 }, { ty }) }, {}, {}, {}, {}, { func }, origin)
    local contracts = Code.CodeContractFactSet(module.id, {
        Code.CodeFuncContractFact(func_id, Code.CodeContractBounds(xs.value, n.value), origin),
    })
    return module, contracts
end

local type_cases = {
    { suffix = "i8", bits = 8, signed = true, ctype = "int8_t", values = { -128, -7, 0, 5, 127 } },
    { suffix = "u8", bits = 8, signed = false, ctype = "uint8_t", values = { 255, 7, 0, 128, 3 } },
    { suffix = "i16", bits = 16, signed = true, ctype = "int16_t", values = { -32768, -19, 0, 30000, 7 } },
    { suffix = "u16", bits = 16, signed = false, ctype = "uint16_t", values = { 65535, 17, 0, 32768, 11 } },
    { suffix = "i32", bits = 32, signed = true, ctype = "int32_t", values = { 2147483647, -17, 0, -2147483648, 31 } },
    { suffix = "u32", bits = 32, signed = false, ctype = "uint32_t", values = { 4294967295, 17, 0, 2147483648, 31 } },
}

local stencil_type_cases = {
    { suffix = "i8", bits = 8, signed = true, ctype = "int8_t", values = { -8, -1, 0, 3, 7 } },
    { suffix = "u8", bits = 8, signed = false, ctype = "uint8_t", values = { 1, 7, 0, 8, 3 } },
    { suffix = "i16", bits = 16, signed = true, ctype = "int16_t", values = { -32, -19, 0, 21, 7 } },
    { suffix = "u16", bits = 16, signed = false, ctype = "uint16_t", values = { 31, 17, 0, 21, 11 } },
    { suffix = "i32", bits = 32, signed = true, ctype = "int32_t", values = { -128, -17, 0, 64, 31 } },
    { suffix = "u32", bits = 32, signed = false, ctype = "uint32_t", values = { 255, 17, 0, 128, 31 } },
    { suffix = "i64", bits = 64, signed = true, ctype = "int64_t", values = { -128, -17, 0, 64, 31 } },
    { suffix = "u64", bits = 64, signed = false, ctype = "uint64_t", values = { 255, 17, 0, 128, 31 } },
    { suffix = "f32", bits = 32, signed = true, float = true, ctype = "float", values = { -2.5, 1.25, 0, 4.5, 3.0 } },
    { suffix = "f64", bits = 64, signed = true, float = true, ctype = "double", values = { -2.5, 1.25, 0, 4.5, 3.0 } },
}

local reductions = {
    { suffix = "add", reduction = Value.ReductionAdd, op = Core.BinAdd, init = "0" },
    { suffix = "mul", reduction = Value.ReductionMul, op = Core.BinMul, init = "1" },
    { suffix = "and", reduction = Value.ReductionAnd, op = Core.BinBitAnd, init = "-1" },
    { suffix = "or", reduction = Value.ReductionOr, op = Core.BinBitOr, init = "0" },
    { suffix = "xor", reduction = Value.ReductionXor, op = Core.BinBitXor, init = "0" },
    { suffix = "min", reduction = Value.ReductionMin, init_for = function(t) return t.signed and (t.bits == 8 and "127" or t.bits == 16 and "32767" or "2147483647") or (t.bits == 8 and "255" or t.bits == 16 and "65535" or "4294967295") end },
    { suffix = "max", reduction = Value.ReductionMax, init_for = function(t) return t.signed and (t.bits == 8 and "-128" or t.bits == 16 and "-32768" or "-2147483648") or "0" end },
}

local float_reductions = {
    { suffix = "add", reduction = Value.ReductionAdd, op = Core.BinAdd, init = "0" },
    { suffix = "mul", reduction = Value.ReductionMul, op = Core.BinMul, init = "1" },
    { suffix = "min", reduction = Value.ReductionMin, init = "9999" },
    { suffix = "max", reduction = Value.ReductionMax, init = "-9999" },
}

local function ty_for_case(tcase)
    if tcase.float then return Code.CodeTyFloat(tcase.bits) end
    return Code.CodeTyInt(tcase.bits, tcase.signed and Code.CodeSigned or Code.CodeUnsigned)
end

local function assert_same_result(case, got, expected, label)
    if case.float then
        local diff = math.abs(tonumber(got) - tonumber(expected))
        assert(diff < 0.0001, label .. " result mismatch: got " .. tostring(got) .. " expected " .. tostring(expected))
    else
        assert(tonumber(got) == tonumber(expected), label .. " result mismatch: got " .. tostring(got) .. " expected " .. tostring(expected))
    end
end

local function compile_with_stencil(case, values, ctype, stem, expected_values)
    local xs = ffi.new(ctype .. "[?]", #values)
    for i = 1, #values do xs[i - 1] = values[i] end
    local module, contracts = build_case(case)
    local rejects, artifacts = {}, {}
    local lj_module, facts = Lower.lower_module(module, {
        contracts = contracts,
        collect_rejects = rejects,
        stencil_reduce_artifact_for = function(func, vocab, op, reduction, plan, info)
            local artifact = StencilC.reduce_array_artifact(reduction, plan, info)
            artifacts[#artifacts + 1] = artifact
            return artifact
        end,
    })
    assert(#rejects == 0, case.name .. " rejected through stencil: " .. tostring(rejects[1] and rejects[1].reason))
    assert(#facts.value.reductions == 1 and facts.value.reductions[1].kind == case.reduction, case.name .. " should derive expected ReductionKind")
    assert(#artifacts == 1, case.name .. " should collect one stencil artifact")
    assert(pvm.classof(artifacts[1].instance.schedule) == Stencil.StencilScheduleAutoVector, case.name .. " should carry an auto-vector stencil schedule")
    assert(pvm.classof(lj_module.funcs[1].machines[1].kind) == LJ.LJMachineStencilCall, case.name .. " should emit LJMachineStencilCall")
    local build, build_err = StencilBinary.compile(T, artifacts, { stem = stem or ("test_luajit_lower_reductions_" .. case.name) })
    assert(build ~= nil, tostring(build_err))
    local compiled, err, src = Emit.compile_module(lj_module, {
        chunk_name = "test_luajit_lower_reductions_" .. case.name,
        stencil_symbols = build.symbols,
    })
    assert(compiled ~= nil, tostring(err) .. "\n" .. tostring(src))
    assert_same_result(case, compiled[case.name](xs, #values), reduce_expect(case, expected_values or values), case.name)
end

do
    local tcase = type_cases[5]
    local case = {
        name = "reduce_without_stencil_provider_rejects",
        ty = ty_for_case(tcase),
        bits = tcase.bits,
        signed = tcase.signed,
        reduction = Value.ReductionAdd,
        op = Core.BinAdd,
        init = "0",
    }
    local module, contracts = build_case(case)
    local rejects = {}
    Lower.lower_module(module, { contracts = contracts, collect_rejects = rejects })
    assert(#rejects == 1, "canonical reduction lowering should require a stencil provider")
    assert(tostring(rejects[1].reason):match("stencil") or tostring(rejects[1].reason):match("select_kernel_lowering"), "unexpected missing-provider reject: " .. tostring(rejects[1].reason))
end

for _, tcase in ipairs(stencil_type_cases) do
    local rs = tcase.float and float_reductions or reductions
    for _, rcase in ipairs(rs) do
        local case = {
            name = "reduce_stencil_" .. rcase.suffix .. "_" .. tcase.suffix,
            ty = ty_for_case(tcase),
            bits = tcase.bits,
            signed = tcase.signed,
            float = tcase.float,
            reduction = rcase.reduction,
            op = rcase.op,
            init = rcase.init or rcase.init_for(tcase),
        }
        compile_with_stencil(case, tcase.values, tcase.ctype)
    end
end

do
    local tcase = type_cases[6]
    local values = tcase.values
    local case = {
        name = "reduce_stride2_add_u32",
        ty = Code.CodeTyInt(32, Code.CodeUnsigned),
        bits = 32,
        signed = false,
        reduction = Value.ReductionAdd,
        op = Core.BinAdd,
        init = "0",
        step = 2,
    }
    local selected = { values[1], values[3], values[5] }
    compile_with_stencil(case, values, "uint32_t", "test_luajit_lower_reductions_stride2", selected)
end

io.write("moonlift luajit_lower_reductions ok\n")
