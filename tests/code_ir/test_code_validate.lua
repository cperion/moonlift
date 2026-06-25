package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

assert(package.loaded["lalin.tree_to_c"] == nil)
assert(package.loaded["lalin.type_to_c"] == nil)

local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local T = pvm.context()
Schema(T)

local Validate = require("lalin.code_validate")(T)
assert(package.loaded["lalin.tree_to_c"] == nil)
assert(package.loaded["lalin.type_to_c"] == nil)

local Core = T.LalinCore
local Code = T.LalinCode

local origin = Code.CodeOriginGenerated("test_code_validate")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local bool = Code.CodeTyBool8
local ptr_i32 = Code.CodeTyDataPtr(i32)

local function has_issue(report, cls)
    for i = 1, #report.issues do
        if pvm.classof(report.issues[i]) == cls then return true, report.issues[i] end
    end
    return false, nil
end

local function param(name, ty)
    return Code.CodeParam(Code.CodeValueId("v:" .. name), name, ty, origin)
end

local function const_inst(id, dst, ty, literal)
    return Code.CodeInst(Code.CodeInstId("inst:" .. id), Code.CodeInstConst(Code.CodeValueId("v:" .. dst), Code.CodeConstLiteral(ty, literal)), origin)
end

local function valid_module()
    local sig = Code.CodeSigId("sig:add")
    local fn = Code.CodeFuncId("fn:add")
    local entry = Code.CodeBlockId("block:entry")
    local a = param("a", i32)
    local b = param("b", i32)
    local sum = Code.CodeValueId("v:sum")
    local inst = Code.CodeInst(
        Code.CodeInstId("inst:sum"),
        Code.CodeInstAlias(sum, i32, a.value),
        origin
    )
    local term = Code.CodeTerm(Code.CodeTermId("term:return"), Code.CodeTermReturn({ sum }), origin)
    local block = Code.CodeBlock(entry, "entry", {}, { inst }, term, origin)
    return Code.CodeModule(
        Code.CodeModuleId("module:valid"),
        { Code.CodeSig(sig, { i32, i32 }, { i32 }) },
        {}, {}, {}, {},
        { Code.CodeFunc(fn, "add", Code.CodeLinkageExport, sig, { a, b }, {}, entry, { block }, origin) },
        origin
    )
end

local report = Validate.validate(valid_module())
assert(#report.issues == 0, "valid module should have no LalinCode validation issues, got " .. tostring(#report.issues))

local bad = valid_module()
local missing = Code.CodeValueId("v:missing")
bad.funcs[1].blocks[1].term = Code.CodeTerm(Code.CodeTermId("term:return_missing"), Code.CodeTermReturn({ missing }), origin)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueMissingValue))

bad = valid_module()
bad.funcs[1].blocks[1].id = Code.CodeBlockId("block:other")
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueMissingBlock))

bad = valid_module()
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = const_inst("dupe", "sum", i32, Core.LitInt("2"))
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueDuplicateValue))

bad = valid_module()
local target = Code.CodeBlockId("block:target")
bad.funcs[1].blocks[1].term = Code.CodeTerm(Code.CodeTermId("term:jump"), Code.CodeTermJump(target, {}), origin)
bad.funcs[1].blocks[#bad.funcs[1].blocks + 1] = Code.CodeBlock(target, "target", { param("target_arg", i32) }, {}, Code.CodeTerm(Code.CodeTermId("term:target_unreachable"), Code.CodeTermUnreachable("test"), origin), origin)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueJumpArity))

bad = valid_module()
target = Code.CodeBlockId("block:target")
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = const_inst("flag", "flag", bool, Core.LitBool(true))
bad.funcs[1].blocks[1].term = Code.CodeTerm(Code.CodeTermId("term:jump_bad_type"), Code.CodeTermJump(target, { Code.CodeValueId("v:flag") }), origin)
bad.funcs[1].blocks[#bad.funcs[1].blocks + 1] = Code.CodeBlock(target, "target", { param("target_i32", i32) }, {}, Code.CodeTerm(Code.CodeTermId("term:target_unreachable2"), Code.CodeTermUnreachable("test"), origin), origin)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueBlockParamMismatch))

bad = valid_module()
local wrong = const_inst("bool", "flag", bool, Core.LitBool(true))
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = wrong
bad.funcs[1].blocks[1].term = Code.CodeTerm(Code.CodeTermId("term:return_bool"), Code.CodeTermReturn({ Code.CodeValueId("v:flag") }), origin)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueTypeMismatch))

bad = valid_module()
local sig = Code.CodeSigId("sig:add")
local extern = Code.CodeExternId("extern:add")
bad.externs = { Code.CodeExtern(extern, "host_add", "host_add", sig, origin) }
local call_dst = Code.CodeValueId("v:call")
local call = Code.CodeInst(Code.CodeInstId("inst:call"), Code.CodeInstCall(call_dst, Code.CodeCallExtern(extern), sig, { Code.CodeValueId("v:a") }), origin)
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = call
bad.funcs[1].blocks[1].term = Code.CodeTerm(Code.CodeTermId("term:return_call"), Code.CodeTermReturn({ call_dst }), origin)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueCallArity))

bad = valid_module()
local missing_sig = Code.CodeSigId("sig:missing")
bad.externs = { Code.CodeExtern(extern, "host_missing", "host_missing", missing_sig, origin) }
call_dst = Code.CodeValueId("v:call")
call = Code.CodeInst(Code.CodeInstId("inst:call_missing_sig"), Code.CodeInstCall(call_dst, Code.CodeCallExtern(extern), missing_sig, { Code.CodeValueId("v:a") }), origin)
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = call
bad.funcs[1].blocks[1].term = Code.CodeTerm(Code.CodeTermId("term:return_missing_sig"), Code.CodeTermReturn({ call_dst }), origin)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueMissingSig))

bad = valid_module()
local other_sig = Code.CodeSigId("sig:other")
bad.sigs[#bad.sigs + 1] = Code.CodeSig(other_sig, { i32 }, { i32 })
bad.externs = { Code.CodeExtern(extern, "host_add", "host_add", sig, origin) }
call_dst = Code.CodeValueId("v:call")
call = Code.CodeInst(Code.CodeInstId("inst:call"), Code.CodeInstCall(call_dst, Code.CodeCallExtern(extern), other_sig, { Code.CodeValueId("v:a") }), origin)
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = call
bad.funcs[1].blocks[1].term = Code.CodeTerm(Code.CodeTermId("term:return_call"), Code.CodeTermReturn({ call_dst }), origin)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueTypeMismatch))

bad = valid_module()
local data = Code.CodeDataId("data:bytes")
bad.data = { Code.CodeData(data, "bytes", Code.CodeLinkageLocal, 8, 8, {}, origin) }
local p = Code.CodeValueId("v:p")
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = Code.CodeInst(
    Code.CodeInstId("inst:dataref"),
    Code.CodeInstGlobalRef(p, Code.CodeGlobalRefData(data), Code.CodeTyCodePtr(Code.CodeSigId("sig:add"))),
    origin
)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueDataCodePointerConfusion))

bad = valid_module()
local global_id = Code.CodeGlobalId("global:g")
bad.globals = { Code.CodeGlobal(global_id, "g", i32, Code.CodeLinkageLocal, 4, 4, {}, origin) }
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = Code.CodeInst(
    Code.CodeInstId("inst:load_global_wrong_ty"),
    Code.CodeInstLoad(Code.CodeValueId("v:load_global"), Code.CodePlaceGlobal(global_id, bool), Code.CodeMemoryAccess(Code.CodeMemoryRead, bool, 1, Code.CodeMayTrap, false, nil)),
    origin
)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueTypeMismatch))

bad = valid_module()
local local_id = Code.CodeLocalId("local:x")
bad.funcs[1].locals = { Code.CodeLocal(local_id, "x", i32, Code.CodeResidenceAddressed, origin) }
bad.funcs[1].blocks[1].insts[#bad.funcs[1].blocks[1].insts + 1] = Code.CodeInst(
    Code.CodeInstId("inst:load_bad_align"),
    Code.CodeInstLoad(Code.CodeValueId("v:load"), Code.CodePlaceLocal(local_id, i32), Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 3, Code.CodeMayTrap, false, nil)),
    origin
)
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueInvalidMemoryAccess))

local emitted = {}
report = Validate.validate(bad, { emit = function(_, issue, phase) emitted[#emitted + 1] = { issue = issue, phase = phase } end })
assert(#emitted == #report.issues and emitted[1].phase == "code")

local rel = Code.CodeReloc(Code.CodeRelocId("reloc:missing"), 0, Code.CodeGlobalRefFunc(Code.CodeFuncId("fn:nope")), 0, origin)
bad = valid_module()
bad.data = { Code.CodeData(Code.CodeDataId("data:rel"), "rel", Code.CodeLinkageLocal, 8, 8, { Code.CodeDataReloc(rel) }, origin) }
report = Validate.validate(bad)
assert(has_issue(report, Code.CodeIssueMissingFunc))

assert(package.loaded["lalin.tree_to_c"] == nil)
assert(package.loaded["lalin.type_to_c"] == nil)
io.write("lalin code_validate ok\n")
