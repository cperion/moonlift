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

local Debugger = require("moonlift.debugger_core")

-- Test 1: Basic stepping with breakpoints
-- Uses a simple program: entry → loop (then compare) → done
do
    local sig = Back.BackSigId("sig:abs_test")
    local func = Back.BackFuncId("abs_test")
    local entry = Back.BackBlockId("entry.abs_test")
    local pos_block = Back.BackBlockId("abs_pos")
    local neg_block = Back.BackBlockId("abs_neg")
    local x = Back.BackValId("x")
    local cond = Back.BackValId("cond")
    local r = Back.BackValId("r")

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
        Back.CmdCompare(cond, Back.BackSIcmpGe, Back.BackShapeScalar(Back.BackI32),
            x, Back.BackValId("zero")),
        Back.CmdBrIf(cond, pos_block, { x }, neg_block, { x }),
        Back.CmdSealBlock(entry),

        -- pos body
        Back.CmdSwitchToBlock(pos_block),
        Back.CmdReturnValue(x),
        Back.CmdSealBlock(pos_block),

        -- neg body
        Back.CmdSwitchToBlock(neg_block),
        Back.CmdIntBinary(r, Back.BackIntSub, Back.BackI32,
            Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose),
            Back.BackValId("zero"), x),
        Back.CmdReturnValue(r),
        Back.CmdSealBlock(neg_block),

        Back.CmdFinishFunc(func),
        Back.CmdFinalizeModule,
    }

    local d = Debugger.new(cmds, { Back = Back })
    d:init()

    -- Should be paused at first block
    assert(d:get_state() == "paused", "expected paused after init")

    -- Set a breakpoint on "abs_pos"
    d:set_breakpoint("abs_pos")
    assert(d.breakpoints["abs_pos"], "breakpoint should be set")

    -- Start execution (steps to first block)
    local block = d:start()
    assert(block == "entry.abs_test", "expected entry.abs_test, got " .. tostring(block))
    assert(d:get_state() == "paused", "expected paused after start")

    -- Set x = 5 (positive → take pos_block)
    d.interpreter.registers[Back.BackValId("x").text] = 5
    d.interpreter.registers[Back.BackValId("zero").text] = 0

    -- Continue (should hit breakpoint at abs_pos)
    local result = d:continue()
    assert(d.interpreter.current_block == "abs_pos",
        "expected abs_pos, got " .. tostring(d.interpreter.current_block))
    print("test_debugger_core: breakpoint hit at abs_pos ok")

    -- Check variables at abs_pos entry
    local vars = d:get_variables()
    print("test_debugger_core: vars at abs_pos: x=" .. tostring(vars.x))

    -- Continue to termination
    local result = d:continue()
    assert(d:is_terminated(), "expected terminated")
    assert(d.interpreter.return_value == 5, "expected 5, got " .. tostring(d.interpreter.return_value))
    print("test_debugger_core: abs(5) = 5 ok")
end

-- Test 2: Source line resolution (no anchors, basic test)
do
    d = Debugger.new({}, { Back = Back })
    d:init()

    local line = d:resolve_line_to_block(5)
    assert(type(line) == "table", "resolve_line_to_block should return table")
    assert(#line == 0, "no anchors → no results")
    print("test_debugger_core: resolve_line_to_block (empty) ok")
end

-- Test 3: Stack trace
do
    local sig = Back.BackSigId("sig:simple")
    local func = Back.BackFuncId("simple")
    local entry = Back.BackBlockId("entry.simple")
    local x = Back.BackValId("x")

    local cmds = {
        Back.CmdCreateSig(sig, { Back.BackI32 }, { Back.BackI32 }),
        Back.CmdDeclareFunc(C.VisibilityExport, func, sig),
        Back.CmdBeginFunc(func),
        Back.CmdCreateBlock(entry),
        Back.CmdAppendBlockParam(entry, x, Back.BackShapeScalar(Back.BackI32)),
        Back.CmdSwitchToBlock(entry),
        Back.CmdBindEntryParams(entry, { x }),
        Back.CmdReturnValue(x),
        Back.CmdSealBlock(entry),
        Back.CmdFinishFunc(func),
        Back.CmdFinalizeModule,
    }

    local d = Debugger.new(cmds, { Back = Back })
    d:init()
    d:start()
    d.interpreter.registers[Back.BackValId("x").text] = 42

    local stack = d:stack_trace()
    assert(type(stack) == "table", "stack_trace should return table")
    assert(#stack >= 1, "stack should have at least 1 frame")
    print("test_debugger_core: stack_trace ok")
end

print("\nmoonlift debugger_core ok")
