package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local V = require("moonlift.back_validate")

local T = pvm.context()
A.Define(T)
local L = V.Define(T)
local C = T.MoonCore
local B = T.MoonBack

local function issue_count(program)
    return #L.validate(program).issues
end

local function has_issue(report, issue)
    for i = 1, #report.issues do
        if report.issues[i] == issue then
            return true
        end
    end
    return false
end

local sig = B.BackSigId("sig:add")
local func = B.BackFuncId("add")
local entry = B.BackBlockId("entry")
local a = B.BackValId("a")
local b = B.BackValId("b")
local r = B.BackValId("r")

local valid_add = B.BackProgram({
    B.CmdCreateSig(sig, { B.BackI32, B.BackI32 }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { a, b }),
    B.CmdIntBinary(r, B.BackIntAdd, B.BackI32, B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), a, b),
    B.CmdReturnValue(r),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
assert(issue_count(valid_add) == 0)

local missing_finalize = B.BackProgram({
    B.CmdCreateSig(sig, { B.BackI32 }, { B.BackI32 }),
})
local missing_report = L.validate(missing_finalize)
assert(has_issue(missing_report, B.BackIssueMissingFinalize))

local nested_func = B.BackFuncId("nested")
local nested_program = B.BackProgram({
    B.CmdBeginFunc(func),
    B.CmdBeginFunc(nested_func),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
local nested_report = L.validate(nested_program)
assert(has_issue(nested_report, B.BackIssueNestedFunction(2, func, nested_func)))

local duplicate_sig = B.BackProgram({
    B.CmdCreateSig(sig, {}, {}),
    B.CmdCreateSig(sig, {}, {}),
    B.CmdFinalizeModule,
})
local duplicate_report = L.validate(duplicate_sig)
assert(has_issue(duplicate_report, B.BackIssueDuplicateSig(2, sig)))

local after_finalize = B.BackProgram({
    B.CmdFinalizeModule,
    B.CmdTrap,
})
local after_report = L.validate(after_finalize)
assert(has_issue(after_report, B.BackIssueCommandAfterFinalize(2)))

local missing_refs = B.BackProgram({
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { a }),
    B.CmdDataAddr(B.BackValId("data.addr"), B.BackDataId("missing:data")),
    B.CmdStackAddr(B.BackValId("slot.addr"), B.BackStackSlotId("missing:slot")),
    B.CmdFuncAddr(B.BackValId("func.addr"), B.BackFuncId("missing:func")),
    B.CmdExternAddr(B.BackValId("extern.addr"), B.BackExternId("missing:extern")),
    B.CmdJump(B.BackBlockId("missing:block"), { B.BackValId("missing:value") }),
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
local refs_report = L.validate(missing_refs)
assert(has_issue(refs_report, B.BackIssueMissingSig(1, sig)))
assert(has_issue(refs_report, B.BackIssueMissingData(6, B.BackDataId("missing:data"))))
assert(has_issue(refs_report, B.BackIssueMissingStackSlot(7, B.BackStackSlotId("missing:slot"))))
assert(has_issue(refs_report, B.BackIssueMissingFunc(8, B.BackFuncId("missing:func"))))
assert(has_issue(refs_report, B.BackIssueMissingExtern(9, B.BackExternId("missing:extern"))))
assert(has_issue(refs_report, B.BackIssueMissingBlock(10, B.BackBlockId("missing:block"))))
assert(has_issue(refs_report, B.BackIssueMissingValue(10, B.BackValId("missing:value"))))

local duplicate_locals = B.BackProgram({
    B.CmdCreateSig(sig, {}, {}),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdCreateStackSlot(B.BackStackSlotId("slot:x"), 4, 4),
    B.CmdCreateStackSlot(B.BackStackSlotId("slot:x"), 4, 4),
    B.CmdConst(B.BackValId("v"), B.BackI32, B.BackLitInt("1")),
    B.CmdConst(B.BackValId("v"), B.BackI32, B.BackLitInt("2")),
    B.CmdReturnVoid,
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
local duplicate_locals_report = L.validate(duplicate_locals)
assert(has_issue(duplicate_locals_report, B.BackIssueDuplicateStackSlot(7, B.BackStackSlotId("slot:x"))))
assert(has_issue(duplicate_locals_report, B.BackIssueDuplicateValue(9, B.BackValId("v"))))

local outside_body = B.BackProgram({
    B.CmdCreateSig(sig, {}, {}),
    B.CmdCreateBlock(entry),
    B.CmdFinalizeModule,
})
local outside_report = L.validate(outside_body)
assert(has_issue(outside_report, B.BackIssueCommandOutsideFunction(2)))

local vec_shape = B.BackShapeVec(B.BackVec(B.BackI32, 4))
local scalar_shape = B.BackShapeScalar(B.BackI32)
local shape_mismatch = B.BackProgram({
    B.CmdCreateSig(sig, {}, {}),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdConst(a, B.BackI32, B.BackLitInt("1")),
    B.CmdConst(b, B.BackI32, B.BackLitInt("2")),
    B.CmdCompare(B.BackValId("bad.cmp"), B.BackIcmpEq, vec_shape, a, b),
    B.CmdReturnVoid,
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
local shape_report = L.validate(shape_mismatch)
assert(has_issue(shape_report, B.BackIssueShapeRequiresScalar(8, vec_shape)))

local ptr_sig = B.BackSigId("sig:load_info")
local ptr_func = B.BackFuncId("load_info")
local p = B.BackValId("p")
local off = B.BackValId("off")
local loaded = B.BackValId("loaded")
local addr = B.BackAddress(B.BackAddrValue(p), off, B.BackProvArg("p"), B.BackPtrInBounds("test address"))
local mem_read = B.BackMemoryInfo(B.BackAccessId("access:load"), B.BackAlignKnown(4), B.BackDerefBytes(4, "test deref"), B.BackNonTrapping("test deref"), B.BackMayNotMove, B.BackAccessRead)
local fact_rich_load = B.BackProgram({
    B.CmdCreateSig(ptr_sig, { B.BackPtr }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, ptr_func, ptr_sig),
    B.CmdBeginFunc(ptr_func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { p }),
    B.CmdConst(off, B.BackIndex, B.BackLitInt("0")),
    B.CmdLoadInfo(loaded, scalar_shape, addr, mem_read),
    B.CmdReturnValue(loaded),
    B.CmdFinishFunc(ptr_func),
    B.CmdFinalizeModule,
})
assert(issue_count(fact_rich_load) == 0)

local bad_mem = B.BackMemoryInfo(B.BackAccessId("access:bad"), B.BackAlignKnown(3), B.BackDerefBytes(2, "too small"), B.BackMayTrap, B.BackMayNotMove, B.BackAccessWrite)
local bad_mem_program = B.BackProgram({
    B.CmdCreateSig(ptr_sig, { B.BackPtr }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, ptr_func, ptr_sig),
    B.CmdBeginFunc(ptr_func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { p }),
    B.CmdConst(off, B.BackIndex, B.BackLitInt("0")),
    B.CmdLoadInfo(loaded, scalar_shape, addr, bad_mem),
    B.CmdReturnValue(loaded),
    B.CmdFinishFunc(ptr_func),
    B.CmdFinalizeModule,
})
local bad_mem_report = L.validate(bad_mem_program)
assert(has_issue(bad_mem_report, B.BackIssueLoadAccessMode(8, B.BackAccessWrite)))
assert(has_issue(bad_mem_report, B.BackIssueInvalidAlignment(8, 3)))
assert(has_issue(bad_mem_report, B.BackIssueDereferenceTooSmall(8, 2, 4)))

local alias_missing_program = B.BackProgram({
    B.CmdCreateSig(ptr_sig, { B.BackPtr }, {}),
    B.CmdDeclareFunc(C.VisibilityExport, ptr_func, ptr_sig),
    B.CmdBeginFunc(ptr_func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { p }),
    B.CmdAliasFact(B.BackNoAlias(B.BackAccessId("missing:a"), B.BackAccessId("missing:b"), "test")),
    B.CmdReturnVoid,
    B.CmdFinishFunc(ptr_func),
    B.CmdFinalizeModule,
})
local alias_missing_report = L.validate(alias_missing_program)
assert(has_issue(alias_missing_report, B.BackIssueMissingAccess(7, B.BackAccessId("missing:a"))))
assert(has_issue(alias_missing_report, B.BackIssueMissingAccess(7, B.BackAccessId("missing:b"))))

local weak_evidence_mem = B.BackMemoryInfo(B.BackAccessId("access:weak"), B.BackAlignKnown(4), B.BackDerefUnknown, B.BackNonTrapping("no deref evidence"), B.BackCanMove("no notrap-independent evidence"), B.BackAccessRead)
local weak_evidence_program = B.BackProgram({
    B.CmdCreateSig(ptr_sig, { B.BackPtr }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, ptr_func, ptr_sig),
    B.CmdBeginFunc(ptr_func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { p }),
    B.CmdConst(off, B.BackIndex, B.BackLitInt("0")),
    B.CmdLoadInfo(loaded, scalar_shape, addr, weak_evidence_mem),
    B.CmdReturnValue(loaded),
    B.CmdFinishFunc(ptr_func),
    B.CmdFinalizeModule,
})
local weak_evidence_report = L.validate(weak_evidence_program)
assert(has_issue(weak_evidence_report, B.BackIssueNonTrappingWithoutDereference(8)))

local movable_maytrap_mem = B.BackMemoryInfo(B.BackAccessId("access:move"), B.BackAlignKnown(4), B.BackDerefBytes(4, "deref"), B.BackMayTrap, B.BackCanMove("not guarded"), B.BackAccessRead)
local movable_maytrap_program = B.BackProgram({
    B.CmdCreateSig(ptr_sig, { B.BackPtr }, { B.BackI32 }),
    B.CmdDeclareFunc(C.VisibilityExport, ptr_func, ptr_sig),
    B.CmdBeginFunc(ptr_func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdBindEntryParams(entry, { p }),
    B.CmdConst(off, B.BackIndex, B.BackLitInt("0")),
    B.CmdLoadInfo(loaded, scalar_shape, addr, movable_maytrap_mem),
    B.CmdReturnValue(loaded),
    B.CmdFinishFunc(ptr_func),
    B.CmdFinalizeModule,
})
local movable_maytrap_report = L.validate(movable_maytrap_program)
assert(has_issue(movable_maytrap_report, B.BackIssueCanMoveWithoutNonTrapping(8)))

local float_scalar = B.BackValId("float.scalar")
local bad_int_semantics = B.BackProgram({
    B.CmdCreateSig(sig, {}, {}),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdConst(a, B.BackF32, B.BackLitFloat("1.0")),
    B.CmdConst(b, B.BackF32, B.BackLitFloat("2.0")),
    B.CmdIntBinary(float_scalar, B.BackIntAdd, B.BackF32, B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), a, b),
    B.CmdReturnVoid,
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
local bad_int_report = L.validate(bad_int_semantics)
assert(has_issue(bad_int_report, B.BackIssueIntScalarExpected(8, B.BackF32)))

local bad_float_semantics = B.BackProgram({
    B.CmdCreateSig(sig, {}, {}),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdConst(a, B.BackI32, B.BackLitInt("1")),
    B.CmdConst(b, B.BackI32, B.BackLitInt("2")),
    B.CmdFloatBinary(float_scalar, B.BackFloatAdd, B.BackI32, B.BackFloatStrict, a, b),
    B.CmdReturnVoid,
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
local bad_float_report = L.validate(bad_float_semantics)
assert(has_issue(bad_float_report, B.BackIssueFloatScalarExpected(8, B.BackI32)))

local target_limited = B.BackProgram({
    B.CmdTargetModel(B.BackTargetModel(B.BackTargetCraneliftJit, { B.BackTargetSupportsShape(B.BackShapeScalar(B.BackI32)) })),
    B.CmdCreateSig(sig, {}, {}),
    B.CmdDeclareFunc(C.VisibilityExport, func, sig),
    B.CmdBeginFunc(func),
    B.CmdCreateBlock(entry),
    B.CmdSwitchToBlock(entry),
    B.CmdConst(a, B.BackI64, B.BackLitInt("1")),
    B.CmdConst(b, B.BackI64, B.BackLitInt("2")),
    B.CmdIntBinary(r, B.BackIntAdd, B.BackI64, B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), a, b),
    B.CmdReturnVoid,
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
local target_limited_report = L.validate(target_limited)
assert(has_issue(target_limited_report, B.BackIssueTargetUnsupportedShape(9, B.BackShapeScalar(B.BackI64))))

print("moonlift back_validate ok")
