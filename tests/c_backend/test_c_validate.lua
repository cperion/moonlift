package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context(); Schema(T)

local Core = T.LalinCore
local C = T.LalinC
local Validate = require("lalin.c_validate")(T)
local Helpers = require("lalin.c_helpers")(T)
local CodeType = require("lalin.code_type")(T)
local Coverage = require("lalin.c_coverage")

local i32 = C.CBackendScalar(Core.ScalarI32)
local i64 = C.CBackendScalar(Core.ScalarI64)
local target = CodeType.default_target({})
local sig_id = C.CBackendFuncSigId("sig_i32_i32_i32")
local sig = C.CBackendFuncSig(sig_id, { i32, i32 }, i32)
local a = C.CBackendLocal(C.CBackendLocalId("a"), C.CBackendName("a"), i32)
local b = C.CBackendLocal(C.CBackendLocalId("b"), C.CBackendName("b"), i32)
local r = C.CBackendLocal(C.CBackendLocalId("r"), C.CBackendName("r"), i32)
local helper_spec = C.CBackendHelperIntBinary(Core.BinAdd, i32, C.CBackendIntWrap)
local helper = C.CBackendHelperUse(Helpers.helper_id(helper_spec), helper_spec)
local entry = C.CBackendBlock(
    C.CBackendLabel("entry"),
    {},
    { C.CBackendHelperCall(r.id, helper.id, { C.CBackendAtomLocal(a.id), C.CBackendAtomLocal(b.id) }) },
    C.CBackendReturn(C.CBackendAtomLocal(r.id))
)
local function blocks_body(blocks)
    return C.CBackendBodyBlocks(blocks[1].label, blocks)
end

local func = C.CBackendFunc(C.CBackendName("add"), "add", Core.VisibilityExport, sig_id, { a, b }, { r }, blocks_body({ entry }))
local unit = C.CBackendUnit("m", target, { sig }, {}, {}, {}, { helper }, { func })
assert(#Validate.validate(unit).issues == 0, "valid unit validates")

local function has_issue(report, cls)
    for i = 1, #report.issues do if asdl.classof(report.issues[i]) == cls then return true end end
    return false
end

local missing_sig = C.CBackendUnit("m", target, {}, {}, {}, {}, { helper }, { func })
assert(has_issue(Validate.validate(missing_sig), C.CBackendIssueMissingSig), "missing sig reported")

local missing_helper = C.CBackendUnit("m", target, { sig }, {}, {}, {}, {}, { func })
assert(has_issue(Validate.validate(missing_helper), C.CBackendIssueMissingHelper), "missing helper reported")

local bad_local_block = C.CBackendBlock(C.CBackendLabel("entry"), {}, {}, C.CBackendReturn(C.CBackendAtomLocal(C.CBackendLocalId("missing"))))
local bad_local_func = C.CBackendFunc(C.CBackendName("badlocal"), "badlocal", Core.VisibilityLocal, sig_id, { a, b }, {}, blocks_body({ bad_local_block }))
assert(has_issue(Validate.validate(C.CBackendUnit("m", target, { sig }, {}, {}, {}, {}, { bad_local_func })), C.CBackendIssueMissingLocal), "missing local reported")

local p = C.CBackendBlockParam(C.CBackendLocalId("p"), i32)
local needs_arg = C.CBackendBlock(C.CBackendLabel("needs_arg"), { p }, {}, C.CBackendReturn(C.CBackendAtomLocal(p.local_id)))
local bad_goto = C.CBackendBlock(C.CBackendLabel("entry"), {}, {}, C.CBackendGoto(C.CBackendLabel("needs_arg"), {}))
local bad_goto_func = C.CBackendFunc(C.CBackendName("badgoto"), "badgoto", Core.VisibilityLocal, sig_id, { a, b }, {}, blocks_body({ bad_goto, needs_arg }))
assert(has_issue(Validate.validate(C.CBackendUnit("m", target, { sig }, {}, {}, {}, {}, { bad_goto_func })), C.CBackendIssueBlockArgCount), "bad block args reported")

local dup_unit = C.CBackendUnit("m", target, { sig, sig }, {}, {}, {}, { helper }, { func, func })
local dup_report = Validate.validate(dup_unit)
assert(has_issue(dup_report, C.CBackendIssueDuplicateSig) and has_issue(dup_report, C.CBackendIssueDuplicateFunc), "duplicate namespaces reported")

local gid = C.CBackendGlobalId("g")
local glob = C.CBackendGlobal(gid, C.CBackendName("g"), Core.VisibilityLocal, C.CBackendDataPtr(nil), 4, 4, { C.CBackendDataBytes(3, "abcdef") })
assert(has_issue(Validate.validate(C.CBackendUnit("m", target, {}, {}, { glob }, {}, {}, {})), C.CBackendIssueDataInitOutOfBounds), "oob global init reported")
local bad_reloc = C.CBackendGlobal(C.CBackendGlobalId("gr"), C.CBackendName("gr"), Core.VisibilityLocal, C.CBackendDataPtr(nil), 8, 8, { C.CBackendDataReloc(0, C.CBackendRelocFunc(C.CBackendName("missing_func")), 0) })
assert(has_issue(Validate.validate(C.CBackendUnit("m", target, {}, {}, { bad_reloc }, {}, {}, {})), C.CBackendIssueMissingFunc), "bad reloc target reported")

local ptr = C.CBackendDataPtr(nil)
local callee = C.CBackendLocal(C.CBackendLocalId("callee"), C.CBackendName("callee"), ptr)
local indirect = C.CBackendBlock(C.CBackendLabel("entry"), {}, { C.CBackendCall(nil, C.CBackendCallIndirect(C.CBackendAtomLocal(callee.id), sig_id), { C.CBackendAtomLocal(a.id), C.CBackendAtomLocal(b.id) }) }, C.CBackendReturn(C.CBackendAtomLocal(a.id)))
local indirect_func = C.CBackendFunc(C.CBackendName("badindirect"), "badindirect", Core.VisibilityLocal, sig_id, { a, b }, { callee }, blocks_body({ indirect }))
assert(has_issue(Validate.validate(C.CBackendUnit("m", target, { sig }, {}, {}, {}, {}, { indirect_func })), C.CBackendIssueIndirectCallNonCodePtr), "data/code pointer confusion reported")

local wrong_helper_local = C.CBackendLocal(C.CBackendLocalId("wide"), C.CBackendName("wide"), i64)
local wrong_helper_block = C.CBackendBlock(C.CBackendLabel("entry"), {}, { C.CBackendHelperCall(wrong_helper_local.id, helper.id, { C.CBackendAtomLocal(wrong_helper_local.id), C.CBackendAtomLocal(wrong_helper_local.id) }) }, C.CBackendReturn(C.CBackendAtomLocal(a.id)))
local wrong_helper_func = C.CBackendFunc(C.CBackendName("badhelper"), "badhelper", Core.VisibilityLocal, sig_id, { a, b }, { wrong_helper_local }, blocks_body({ wrong_helper_block }))
assert(has_issue(Validate.validate(C.CBackendUnit("m", target, { sig }, {}, {}, {}, { helper }, { wrong_helper_func })), C.CBackendIssueHelperSignatureMismatch), "helper mismatch reported")

local place = C.CBackendPlaceLocal(a.id, i32)
local place_block = C.CBackendBlock(C.CBackendLabel("entry"), {}, { C.CBackendPlaceStore(place, C.CBackendAtomLiteral(i64, Core.LitInt("1"))) }, C.CBackendReturn(C.CBackendAtomLocal(a.id)))
local place_func = C.CBackendFunc(C.CBackendName("badplace"), "badplace", Core.VisibilityLocal, sig_id, { a, b }, {}, blocks_body({ place_block }))
assert(has_issue(Validate.validate(C.CBackendUnit("m", target, { sig }, {}, {}, {}, {}, { place_func })), C.CBackendIssuePlaceTypeMismatch), "place mismatch reported")

local atomic_access = C.CBackendMemoryAccess(i32, 4, C.CBackendMayTrap, false, Core.AtomicSeqCst)
local atomic_spec = C.CBackendHelperAtomicLoad(atomic_access)
local atomic = C.CBackendHelperUse(Helpers.helper_id(atomic_spec), atomic_spec)
assert(has_issue(Validate.validate(C.CBackendUnit("m", CodeType.default_target({ dialect = "c99" }), {}, {}, {}, {}, { atomic }, {})), C.CBackendIssueInvalidTargetFeature), "invalid atomic feature reported")

local td = C.CBackendStructDecl(C.CTypeId("m", "NoAssert"), { C.CBackendField(C.CBackendName("x"), i32, 0, 4, 4) }, nil, nil)
assert(has_issue(Validate.validate(C.CBackendUnit("m", target, {}, { td }, {}, {}, {}, {})), C.CBackendIssueLayoutAssertionMissing), "missing layout assertion reported")

local saved = Coverage.all_tables()["LalinTree.Expr"].ExprLit.status
Coverage.all_tables()["LalinTree.Expr"].ExprLit.status = "bogus"
local cov_report = Validate.validate(unit)
Coverage.all_tables()["LalinTree.Expr"].ExprLit.status = saved
assert(has_issue(cov_report, C.CBackendIssueCoverageMissing), "coverage mismatch reported")

local abi_issue = C.CBackendIssueAbiMismatch("site", sig_id, "reason")
assert(has_issue(Validate.validate_input(C.CBackendValidationInput(unit, {}, { abi_issue })), C.CBackendIssueAbiMismatch), "ABI mismatch pass-through reported")

local sig0_id = C.CBackendFuncSigId("sig_i32_void")
local sig0 = C.CBackendFuncSig(sig0_id, {}, i32)
local x = C.CBackendLocal(C.CBackendLocalId("x"), C.CBackendName("x"), i32)
local read_uninit_block = C.CBackendBlock(C.CBackendLabel("entry"), {}, {}, C.CBackendReturn(C.CBackendAtomLocal(x.id)))
local read_uninit_func = C.CBackendFunc(C.CBackendName("read_uninit"), "read_uninit", Core.VisibilityLocal, sig0_id, {}, { x }, blocks_body({ read_uninit_block }))
local storage_uninit = C.CBackendStorageRecord(read_uninit_func.name, { C.CBackendLocalStorage(x.id, x.name, x.ty, C.CBackendResidenceValue, C.CBackendLocalUninitialized, false) })
local uninit_unit = C.CBackendUnit("m", target, { sig0 }, {}, {}, {}, {}, { read_uninit_func })
assert(has_issue(Validate.validate_input(C.CBackendValidationInput(uninit_unit, { storage_uninit }, {})), C.CBackendIssueUninitializedLocal), "uninitialized local reported")

local addr_block = C.CBackendBlock(C.CBackendLabel("entry"), {}, {}, C.CBackendReturn(C.CBackendAtomLiteral(i32, Core.LitInt("0"))))
local addr_func = C.CBackendFunc(C.CBackendName("addr_bad"), "addr_bad", Core.VisibilityLocal, sig0_id, {}, { x }, blocks_body({ addr_block }))
local storage_addr = C.CBackendStorageRecord(addr_func.name, { C.CBackendLocalStorage(x.id, x.name, x.ty, C.CBackendResidenceValue, C.CBackendLocalInitialized, true) })
local addr_unit = C.CBackendUnit("m", target, { sig0 }, {}, {}, {}, {}, { addr_func })
assert(has_issue(Validate.validate_input(C.CBackendValidationInput(addr_unit, { storage_addr }, {})), C.CBackendIssueUnmaterializedAddressTakenValue), "unmaterialized address-taken value reported")

io.write("lalin c_validate ok\n")
