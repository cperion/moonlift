package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Parse = require("moonlift.parse").Define(T)
local OpenFacts = require("moonlift.open_facts").Define(T)
local OpenValidate = require("moonlift.open_validate").Define(T)
local OpenExpand = require("moonlift.open_expand").Define(T)
local ClosureConvert = require("moonlift.closure_convert").Define(T)
local Typecheck = require("moonlift.tree_typecheck").Define(T)
local Layout = require("moonlift.sem_layout_resolve").Define(T)
local TreeToCode = require("moonlift.tree_to_code").Define(T)
local CodeValidate = require("moonlift.code_validate").Define(T)
local CodeToBack = require("moonlift.code_to_back").Define(T)
local BackValidate = require("moonlift.back_validate").Define(T)
local Jit = require("moonlift.back_jit").Define(T)
local Pipeline = require("moonlift.frontend_pipeline").Define(T)

local Back = T.MoonBack
local Code = T.MoonCode
local Core = T.MoonCore
local Ty = T.MoonType
local Sem = T.MoonSem

local function assert_no_issues(label, issues)
    assert(#issues == 0, label .. " expected no issues, got " .. tostring(#issues))
end

local function code_pipeline(src)
    local parsed = Parse.parse_module(src)
    assert_no_issues("parse", parsed.issues)
    local expanded = OpenExpand.module(parsed.module)
    assert_no_issues("open", OpenValidate.validate(OpenFacts.facts_of_module(expanded)).issues)
    local checked = Typecheck.check_module(ClosureConvert.module(expanded))
    assert_no_issues("typecheck", checked.issues)
    local resolved = Layout.module(checked.module)
    local code_module = TreeToCode.module(resolved)
    assert_no_issues("code", CodeValidate.validate(code_module).issues)
    return code_module
end

local code_module = code_pipeline([[
func add_i32_code(a: i32, b: i32): i32
    return a + b
end

func max_i32_code(a: i32, b: i32): i32
    return select(a > b, a, b)
end

func branch_i32_code(a: i32, b: i32): i32
    if a > b then return a else return b end
end

func classify_i32_code(n: i32): i32
    return switch n do
    case 1 then 10
    case 2 then 20
    default then 0
    end
end

func inc_i32_code(x: i32): i32
    return x + 1
end

func direct_call_i32_code(x: i32): i32
    return inc_i32_code(x)
end

func indirect_call_i32_code(x: i32): i32
    let f: func(i32): i32 = inc_i32_code
    return f(x)
end
]])

local program = CodeToBack.module(code_module)
local report = BackValidate.validate(program)
assert_no_issues("back", report.issues)

local saw_add, saw_select, saw_branch, saw_switch, saw_call, saw_func_addr = false, false, false, false, false, false
for _, cmd in ipairs(program.cmds) do
    local cls = pvm.classof(cmd)
    if cls == Back.CmdIntBinary then saw_add = true end
    if cls == Back.CmdSelect then saw_select = true end
    if cls == Back.CmdBrIf then saw_branch = true end
    if cls == Back.CmdSwitchInt then saw_switch = true end
    if cls == Back.CmdCall then saw_call = true end
    if cls == Back.CmdFuncAddr then saw_func_addr = true end
end
assert(saw_add, "CodeInstBinary should lower to CmdIntBinary")
assert(saw_select, "CodeInstSelect should lower to CmdSelect")
assert(saw_branch, "CodeTermBranch should lower to CmdBrIf")
assert(saw_switch, "CodeTermSwitch should lower to CmdSwitchInt")
assert(saw_call, "CodeInstCall should lower to CmdCall")
assert(saw_func_addr, "function values should lower to CmdFuncAddr")

local artifact = Jit.jit():compile(program)
local add = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer(Back.BackFuncId("add_i32_code")))
local max = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer(Back.BackFuncId("max_i32_code")))
local branch = ffi.cast("int32_t (*)(int32_t, int32_t)", artifact:getpointer(Back.BackFuncId("branch_i32_code")))
local classify = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(Back.BackFuncId("classify_i32_code")))
local direct = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(Back.BackFuncId("direct_call_i32_code")))
local indirect = ffi.cast("int32_t (*)(int32_t)", artifact:getpointer(Back.BackFuncId("indirect_call_i32_code")))
assert(add(20, 22) == 42)
assert(max(4, 9) == 9 and max(12, 7) == 12)
assert(branch(4, 9) == 9 and branch(12, 7) == 12)
assert(classify(1) == 10 and classify(2) == 20 and classify(99) == 0)
assert(direct(41) == 42)
assert(indirect(41) == 42)
artifact:free()

local public_src = [[
func public_inc_i32_code(x: i32): i32
    return x + 1
end

func public_sum_i32_code(xs: ptr(i32), n: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

func public_direct_call_i32_code(x: i32): i32
    return public_inc_i32_code(x)
end

func public_indirect_call_i32_code(x: i32): i32
    let f: func(i32): i32 = public_inc_i32_code
    return f(x)
end
]]

local public_result = Pipeline.parse_and_lower(public_src, { site = "test_code_to_back:public" })
assert(public_result.code_module ~= nil, "public native pipeline should expose CodeModule")
assert(public_result.code_report ~= nil and #public_result.code_report.issues == 0, "public code validation issues")
assert(#public_result.back_report.issues == 0, "public back validation issues")
local public_artifact = Jit.jit():compile(public_result.program)
local public_sum = ffi.cast("int32_t (*)(const int32_t*, int32_t)", public_artifact:getpointer(Back.BackFuncId("public_sum_i32_code")))
local public_direct = ffi.cast("int32_t (*)(int32_t)", public_artifact:getpointer(Back.BackFuncId("public_direct_call_i32_code")))
local public_indirect = ffi.cast("int32_t (*)(int32_t)", public_artifact:getpointer(Back.BackFuncId("public_indirect_call_i32_code")))
local public_xs = ffi.new("int32_t[4]", { 5, 6, 7, 8 })
assert(public_sum(public_xs, 4) == 26)
assert(public_direct(41) == 42)
assert(public_indirect(41) == 42)
public_artifact:free()

local fh = assert(io.open("lua/moonlift/code_to_back.lua", "r"))
local source = fh:read("*a"); fh:close()
assert(not source:find("ctx%." .. "view_defs"), "Back lowering must not keep hidden view-def side table")
assert(not source:find("collect_" .. "view_defs"), "Back lowering must not pre-scan view defs")
assert(not source:find("view_" .. "parts"), "Back lowering must not use view component side table")

local pair_named = Code.CodeTyNamed("M", "Pair", Ty.TNamed(Ty.TypeRefGlobal("M", "Pair")))
local pair_sig = Code.CodeSigId("sig_pair_sret")
local pair_func = Code.CodeFuncId("fn:id_pair_sret")
local pair_arg = Code.CodeValueId("v:id_pair_sret:p")
local pair_entry = Code.CodeBlockId("block:id_pair_sret:entry")
local pair_module = Code.CodeModule(Code.CodeModuleId("module:pair_sret"),
    { Code.CodeSig(pair_sig, { pair_named }, { pair_named }) }, {}, {}, {}, {},
    { Code.CodeFunc(pair_func, "id_pair_sret", Code.CodeLinkageLocal, pair_sig,
        { Code.CodeParam(pair_arg, "p", pair_named, Code.CodeOriginUnknown) }, {}, pair_entry,
        { Code.CodeBlock(pair_entry, "entry", {}, {}, Code.CodeTerm(Code.CodeTermId("term:id_pair_sret"), Code.CodeTermReturn({ pair_arg }), Code.CodeOriginUnknown), Code.CodeOriginUnknown) },
        Code.CodeOriginUnknown) }, Code.CodeOriginUnknown)
local pair_env = Sem.LayoutEnv({ Sem.LayoutNamed("M", "Pair", { Sem.FieldLayout("a", 0, Ty.TScalar(Core.ScalarI32)), Sem.FieldLayout("b", 4, Ty.TScalar(Core.ScalarI32)) }, 8, 4) })
local pair_program = CodeToBack.module(pair_module, { layout_env = pair_env, validate = false })
local pair_report = BackValidate.validate(pair_program)
assert_no_issues("pair sret back", pair_report.issues)
local saw_pair_sig, saw_pair_memcpy = false, false
for _, cmd in ipairs(pair_program.cmds) do
    if pvm.classof(cmd) == Back.CmdCreateSig and #cmd.params == 2 and #cmd.results == 0 then saw_pair_sig = true end
    if pvm.classof(cmd) == Back.CmdMemcpy then saw_pair_memcpy = true end
end
assert(saw_pair_sig and saw_pair_memcpy, "named aggregate result must lower as ordinary sret ABI with memcpy")

ffi.cdef[[
typedef struct { int32_t *data; intptr_t len; intptr_t stride; } ml_test_view_i32;
]]
local i32_ty = Code.CodeTyInt(32, Code.CodeSigned)
local view_ty = Code.CodeTyView(i32_ty)
local view_sig = Code.CodeSigId("sig_view_sret")
local view_func = Code.CodeFuncId("fn:view_id")
local view_arg = Code.CodeValueId("v:view_id:v")
local view_entry = Code.CodeBlockId("block:view_id:entry")
local view_module = Code.CodeModule(Code.CodeModuleId("module:view_sret"),
    { Code.CodeSig(view_sig, { view_ty }, { view_ty }) }, {}, {}, {}, {},
    { Code.CodeFunc(view_func, "view_id", Code.CodeLinkageExport, view_sig,
        { Code.CodeParam(view_arg, "v", view_ty, Code.CodeOriginUnknown) }, {}, view_entry,
        { Code.CodeBlock(view_entry, "entry", {}, {}, Code.CodeTerm(Code.CodeTermId("term:view_id"), Code.CodeTermReturn({ view_arg }), Code.CodeOriginUnknown), Code.CodeOriginUnknown) },
        Code.CodeOriginUnknown) }, Code.CodeOriginUnknown)
local view_program = CodeToBack.module(view_module, { validate = false })
local view_report = BackValidate.validate(view_program)
assert_no_issues("view sret back", view_report.issues)
local saw_view_sig, view_stores = false, 0
for _, cmd in ipairs(view_program.cmds) do
    if pvm.classof(cmd) == Back.CmdCreateSig and #cmd.params == 4 and #cmd.results == 0 then saw_view_sig = true end
    if pvm.classof(cmd) == Back.CmdStoreInfo then view_stores = view_stores + 1 end
end
assert(saw_view_sig, "view result must lower as sret + three view components")
assert(view_stores == 3, "view sret return should store data/len/stride, saw " .. tostring(view_stores))
local view_artifact = Jit.jit():compile(view_program)
local view_id = ffi.cast("void (*)(ml_test_view_i32*, int32_t*, intptr_t, intptr_t)", view_artifact:getpointer(Back.BackFuncId("view_id")))
local view_data = ffi.new("int32_t[3]", { 11, 22, 33 })
local view_out = ffi.new("ml_test_view_i32[1]")
view_id(view_out, view_data, 3, 1)
assert(view_out[0].data[2] == 33, "view sret data pointer was not preserved")
assert(tonumber(view_out[0].len) == 3, "view sret len was " .. tostring(view_out[0].len))
assert(tonumber(view_out[0].stride) == 1, "view sret stride was " .. tostring(view_out[0].stride))
view_artifact:free()

local u32_ty = Code.CodeTyInt(32, Code.CodeUnsigned)
local intr_sig = Code.CodeSigId("sig_intrinsic_rotl")
local intr_func = Code.CodeFuncId("fn:intrinsic_rotl")
local intr_arg = Code.CodeValueId("v:intrinsic_rotl:x")
local intr_one = Code.CodeValueId("v:intrinsic_rotl:one")
local intr_pc = Code.CodeValueId("v:intrinsic_rotl:pc")
local intr_out = Code.CodeValueId("v:intrinsic_rotl:out")
local intr_entry = Code.CodeBlockId("block:intrinsic_rotl:entry")
local intr_module = Code.CodeModule(Code.CodeModuleId("module:intrinsic_rotl"),
    { Code.CodeSig(intr_sig, { u32_ty }, { u32_ty }) }, {}, {}, {}, {},
    { Code.CodeFunc(intr_func, "intrinsic_rotl", Code.CodeLinkageExport, intr_sig,
        { Code.CodeParam(intr_arg, "x", u32_ty, Code.CodeOriginUnknown) }, {}, intr_entry,
        { Code.CodeBlock(intr_entry, "entry", {}, {
            Code.CodeInst(Code.CodeInstId("inst:intrinsic_rotl:one"), Code.CodeInstConst(intr_one, Code.CodeConstLiteral(u32_ty, Core.LitInt("1"))), Code.CodeOriginUnknown),
            Code.CodeInst(Code.CodeInstId("inst:intrinsic_rotl:pc"), Code.CodeInstIntrinsic(intr_pc, Core.IntrinsicPopcount, u32_ty, { intr_arg }), Code.CodeOriginUnknown),
            Code.CodeInst(Code.CodeInstId("inst:intrinsic_rotl:out"), Code.CodeInstIntrinsic(intr_out, Core.IntrinsicRotl, u32_ty, { intr_pc, intr_one }), Code.CodeOriginUnknown),
        }, Code.CodeTerm(Code.CodeTermId("term:intrinsic_rotl"), Code.CodeTermReturn({ intr_out }), Code.CodeOriginUnknown), Code.CodeOriginUnknown) },
        Code.CodeOriginUnknown) }, Code.CodeOriginUnknown)
local intr_program = CodeToBack.module(intr_module, { validate = false })
local intr_report = BackValidate.validate(intr_program)
assert_no_issues("intrinsic rotl back", intr_report.issues)
local saw_intrinsic, saw_rotate = false, false
for _, cmd in ipairs(intr_program.cmds) do
    if pvm.classof(cmd) == Back.CmdIntrinsic and cmd.op == Back.BackIntrinsicPopcount then saw_intrinsic = true end
    if pvm.classof(cmd) == Back.CmdRotate and cmd.op == Back.BackRotateLeft then saw_rotate = true end
end
assert(saw_intrinsic and saw_rotate, "CodeInstIntrinsic must lower to CmdIntrinsic and CmdRotate")
local intr_artifact = Jit.jit():compile(intr_program)
local intrinsic_rotl = ffi.cast("uint32_t (*)(uint32_t)", intr_artifact:getpointer(Back.BackFuncId("intrinsic_rotl")))
assert(intrinsic_rotl(0x0000000f) == 8, "popcount(0xf)=4; rotl(4,1)=8")
intr_artifact:free()

local f64_ty = Code.CodeTyFloat(64)
local abs_sig = Code.CodeSigId("sig_intrinsic_abs_f64")
local abs_func = Code.CodeFuncId("fn:intrinsic_abs_f64")
local abs_arg = Code.CodeValueId("v:intrinsic_abs_f64:x")
local abs_out = Code.CodeValueId("v:intrinsic_abs_f64:out")
local abs_entry = Code.CodeBlockId("block:intrinsic_abs_f64:entry")
local abs_module = Code.CodeModule(Code.CodeModuleId("module:intrinsic_abs_f64"),
    { Code.CodeSig(abs_sig, { f64_ty }, { f64_ty }) }, {}, {}, {}, {},
    { Code.CodeFunc(abs_func, "intrinsic_abs_f64", Code.CodeLinkageExport, abs_sig,
        { Code.CodeParam(abs_arg, "x", f64_ty, Code.CodeOriginUnknown) }, {}, abs_entry,
        { Code.CodeBlock(abs_entry, "entry", {}, {
            Code.CodeInst(Code.CodeInstId("inst:intrinsic_abs_f64:out"), Code.CodeInstIntrinsic(abs_out, Core.IntrinsicAbs, f64_ty, { abs_arg }), Code.CodeOriginUnknown),
        }, Code.CodeTerm(Code.CodeTermId("term:intrinsic_abs_f64"), Code.CodeTermReturn({ abs_out }), Code.CodeOriginUnknown), Code.CodeOriginUnknown) },
        Code.CodeOriginUnknown) }, Code.CodeOriginUnknown)
local abs_program = CodeToBack.module(abs_module, { validate = false })
local abs_report = BackValidate.validate(abs_program)
assert_no_issues("intrinsic abs f64 back", abs_report.issues)
local abs_artifact = Jit.jit():compile(abs_program)
local intrinsic_abs_f64 = ffi.cast("double (*)(double)", abs_artifact:getpointer(Back.BackFuncId("intrinsic_abs_f64")))
assert(intrinsic_abs_f64(-3.5) == 3.5, "f64 abs intrinsic should lower to fabs")
abs_artifact:free()

print("moonlift code_to_back ok")
