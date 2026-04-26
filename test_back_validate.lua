package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local V = require("moonlift.back_validate")

local T = pvm.context()
A.Define(T)
local L = V.Define(T)
local C = T.Moon2Core
local B = T.Moon2Back

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
    B.CmdBinary(r, B.BackIadd, B.BackShapeScalar(B.BackI32), a, b),
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
    B.CmdBinary(B.BackValId("bad.vec"), B.BackVecIadd, scalar_shape, a, b),
    B.CmdCompare(B.BackValId("bad.cmp"), B.BackIcmpEq, vec_shape, a, b),
    B.CmdReturnVoid,
    B.CmdFinishFunc(func),
    B.CmdFinalizeModule,
})
local shape_report = L.validate(shape_mismatch)
assert(has_issue(shape_report, B.BackIssueShapeRequiresVector(8, scalar_shape)))
assert(has_issue(shape_report, B.BackIssueShapeRequiresScalar(9, vec_shape)))

print("moonlift back_validate ok")
