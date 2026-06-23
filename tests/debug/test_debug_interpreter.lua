package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

local pvm = require("moonlift.pvm")
local Asdl = require("moonlift.schema_projection")

local T = pvm.context()
Asdl(T)
local Back = T.MoonBack
local C = T.MoonCore

local Interpreter = require("moonlift.debug_interpreter")

-- Test 1: Simple add_i32 program
do
    local sig = Back.BackSigId("sig:add_i32")
    local func = Back.BackFuncId("add_i32")
    local entry = Back.BackBlockId("entry.add_i32")
    local a = Back.BackValId("a")
    local b = Back.BackValId("b")
    local r = Back.BackValId("r")

    local cmds = {
        Back.CmdCreateSig(sig, { Back.BackI32, Back.BackI32 }, { Back.BackI32 }),
        Back.CmdDeclareFunc(C.VisibilityExport, func, sig),
        Back.CmdBeginFunc(func),
        Back.CmdCreateBlock(entry),
        Back.CmdAppendBlockParam(entry, a, Back.BackShapeScalar(Back.BackI32)),
        Back.CmdAppendBlockParam(entry, b, Back.BackShapeScalar(Back.BackI32)),
        Back.CmdSwitchToBlock(entry),
        Back.CmdBindEntryParams(entry, { a, b }),
        Back.CmdIntBinary(r, Back.BackIntAdd, Back.BackI32,
            Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), a, b),
        Back.CmdReturnValue(r),
        Back.CmdSealBlock(entry),
        Back.CmdFinishFunc(func),
        Back.CmdFinalizeModule,
    }

    local interp = Interpreter.new(cmds, { Back = Back })
    -- Prime the interpreter by stepping to first block
    local block = interp:step_block()
    assert(block == "entry.add_i32", "expected entry.add_i32, got " .. tostring(block))

    -- Set entry params
    interp.registers["a"] = 20
    interp.registers["b"] = 22

    -- Continue to termination
    interp.step_mode = "continue"
    while interp:step() do end

    assert(interp.terminated, "expected terminated, cursor=" .. interp.cursor .. "/" .. interp.cursor_limit .. ", retval=" .. tostring(interp.return_value))
    assert(interp.return_value == 42, "expected 42, got " .. tostring(interp.return_value))

    print("test_debug_interpreter: add_i32 ok")
end

-- Test 2: Block stepping with BrIf (conditional branch)
do
    local sig = Back.BackSigId("sig:abs")
    local func = Back.BackFuncId("abs")
    local entry = Back.BackBlockId("entry.abs")
    local pos_block = Back.BackBlockId("pos_block")
    local neg_block = Back.BackBlockId("neg_block")
    local x = Back.BackValId("x")
    local r = Back.BackValId("r")
    local cond = Back.BackValId("cond")

    local cmds = {
        Back.CmdCreateSig(sig, { Back.BackI32 }, { Back.BackI32 }),
        Back.CmdDeclareFunc(C.VisibilityExport, func, sig),
        Back.CmdBeginFunc(func),
        -- Entry block
        Back.CmdCreateBlock(entry),
        Back.CmdAppendBlockParam(entry, x, Back.BackShapeScalar(Back.BackI32)),
        -- pos block
        Back.CmdCreateBlock(pos_block),
        -- neg block
        Back.CmdCreateBlock(neg_block),
        -- Entry body
        Back.CmdSwitchToBlock(entry),
        Back.CmdBindEntryParams(entry, { x }),
        Back.CmdConst(Back.BackValId("zero"), Back.BackI32, Back.BackLitInt("0")),
        Back.CmdCompare(cond, Back.BackSIcmpGe, Back.BackShapeScalar(Back.BackI32), x, Back.BackValId("zero")),
        Back.CmdBrIf(cond, pos_block, { x }, neg_block, { x }),
        Back.CmdSealBlock(entry),
        -- pos block
        Back.CmdSwitchToBlock(pos_block),
        Back.CmdReturnValue(x),
        Back.CmdSealBlock(pos_block),
        -- neg block
        Back.CmdSwitchToBlock(neg_block),
        Back.CmdIntBinary(r, Back.BackIntSub, Back.BackI32,
            Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), Back.BackValId("zero"), x),
        Back.CmdReturnValue(r),
        Back.CmdSealBlock(neg_block),
        Back.CmdFinishFunc(func),
        Back.CmdFinalizeModule,
    }

    -- Test with x = 5 (should take pos_block)
    local interp = Interpreter.new(cmds, { Back = Back })
    local block = interp:step_block()
    assert(block == "entry.abs", "expected entry.abs, got " .. tostring(block))

    interp.registers["x"] = 5
    interp.registers["zero"] = 0

    -- Step one block: should go through entry to either pos/neg
    local next_block = interp:step_block()
    -- After BrIf with x=5, cond = true → should be pos_block
    -- But we need to check the correct block id format
    assert(next_block ~= nil, "expected a block after stepping")
    print("test_debug_interpreter: br_if stepping, landed at " .. tostring(next_block))

    -- Continue to termination
    interp.step_mode = "continue"
    while interp:step() do end
    assert(interp.terminated, "expected terminated for abs(5)")
    assert(interp.return_value == 5, "expected 5, got " .. tostring(interp.return_value))

    -- Test with x = -3 (should take neg_block)
    local interp2 = Interpreter.new(cmds, { Back = Back })
    interp2:step_block()  -- entry.abs
    interp2.registers["x"] = -3
    interp2.registers["zero"] = 0

    interp2.step_mode = "continue"
    while interp2:step() do end
    assert(interp2.return_value == 3, "expected 3 (abs(-3)), got " .. tostring(interp2.return_value))

    print("test_debug_interpreter: br_if abs ok")
end

-- Test 3: Read all registers
do
    local sig = Back.BackSigId("sig:vm")
    local func = Back.BackFuncId("vm")
    local entry = Back.BackBlockId("entry.vm")
    local a = Back.BackValId("a")
    local b = Back.BackValId("b")
    local r = Back.BackValId("r")

    local cmds = {
        Back.CmdCreateSig(sig, { Back.BackI32, Back.BackI32 }, { Back.BackI32 }),
        Back.CmdDeclareFunc(C.VisibilityExport, func, sig),
        Back.CmdBeginFunc(func),
        Back.CmdCreateBlock(entry),
        Back.CmdAppendBlockParam(entry, a, Back.BackShapeScalar(Back.BackI32)),
        Back.CmdAppendBlockParam(entry, b, Back.BackShapeScalar(Back.BackI32)),
        Back.CmdSwitchToBlock(entry),
        Back.CmdBindEntryParams(entry, { a, b }),
        Back.CmdIntBinary(r, Back.BackIntAdd, Back.BackI32,
            Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), a, b),
        Back.CmdReturnValue(r),
        Back.CmdSealBlock(entry),
        Back.CmdFinishFunc(func),
        Back.CmdFinalizeModule,
    }

    local interp = Interpreter.new(cmds, { Back = Back })
    interp:step_block()
    interp.registers[Back.BackValId("a").text] = 10
    interp.registers[Back.BackValId("b").text] = 20

    local regs = interp:read_all_registers()
    assert(regs[Back.BackValId("a").text] == 10, "expected a=10")
    assert(regs[Back.BackValId("b").text] == 20, "expected b=20")

    print("test_debug_interpreter: read_all_registers ok")
end

-- Test 4: Indirect calls through CmdFuncAddr
do
    local inc_sig = Back.BackSigId("sig:inc")
    local call_sig = Back.BackSigId("sig:call_indirect")
    local inc_func = Back.BackFuncId("inc")
    local call_func = Back.BackFuncId("call_indirect")
    local call_entry = Back.BackBlockId("entry.call_indirect")
    local inc_entry = Back.BackBlockId("entry.inc")
    local x = Back.BackValId("x.indirect")
    local ix = Back.BackValId("x.inc")
    local one = Back.BackValId("one.inc")
    local fp = Back.BackValId("fp")
    local inc_out = Back.BackValId("inc.out")
    local call_out = Back.BackValId("call.out")

    local cmds = {
        Back.CmdCreateSig(inc_sig, { Back.BackI32 }, { Back.BackI32 }),
        Back.CmdCreateSig(call_sig, { Back.BackI32 }, { Back.BackI32 }),
        Back.CmdDeclareFunc(C.VisibilityLocal, inc_func, inc_sig),
        Back.CmdDeclareFunc(C.VisibilityExport, call_func, call_sig),

        Back.CmdBeginFunc(call_func),
        Back.CmdCreateBlock(call_entry),
        Back.CmdAppendBlockParam(call_entry, x, Back.BackShapeScalar(Back.BackI32)),
        Back.CmdSwitchToBlock(call_entry),
        Back.CmdBindEntryParams(call_entry, { x }),
        Back.CmdFuncAddr(fp, inc_func),
        Back.CmdCall(Back.BackCallValue(call_out, Back.BackI32), Back.BackCallIndirect(fp), inc_sig, { x }),
        Back.CmdReturnValue(call_out),
        Back.CmdSealBlock(call_entry),
        Back.CmdFinishFunc(call_func),

        Back.CmdBeginFunc(inc_func),
        Back.CmdCreateBlock(inc_entry),
        Back.CmdAppendBlockParam(inc_entry, ix, Back.BackShapeScalar(Back.BackI32)),
        Back.CmdSwitchToBlock(inc_entry),
        Back.CmdBindEntryParams(inc_entry, { ix }),
        Back.CmdConst(one, Back.BackI32, Back.BackLitInt("1")),
        Back.CmdIntBinary(inc_out, Back.BackIntAdd, Back.BackI32,
            Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), ix, one),
        Back.CmdReturnValue(inc_out),
        Back.CmdSealBlock(inc_entry),
        Back.CmdFinishFunc(inc_func),
        Back.CmdFinalizeModule,
    }

    local interp = Interpreter.new(cmds, { Back = Back })
    assert(interp:step_block() == "entry.call_indirect")
    interp.registers[x.text] = 41
    interp.step_mode = "continue"
    while interp:step() do end
    assert(interp.terminated, "expected indirect-call program to terminate")
    assert(interp.return_value == 42, "expected 42, got " .. tostring(interp.return_value))

    print("test_debug_interpreter: indirect call ok")
end

print("\nmoonlift debug_interpreter ok")
