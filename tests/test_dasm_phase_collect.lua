package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.asdl")
local Collect = require("back.dasm.phases.collect_module")
local Mx = require("back.dasm.model")

local T = pvm.context()
A2.Define(T)
Mx.set_context(T)

local B = T.MoonBack
local C = T.MoonCore
local D = T.MoonDasm

local function sid(t) return B.BackSigId(t) end
local function fid(t) return B.BackFuncId(t) end
local function bid(t) return B.BackBlockId(t) end
local function vid(t) return B.BackValId(t) end

local i32 = B.BackI32

local program = B.BackProgram({
    B.CmdCreateSig(sid("sig:f"), { i32 }, { i32 }),
    B.CmdDeclareFunc(C.VisibilityExport, fid("f"), sid("sig:f")),
    B.CmdBeginFunc(fid("f")),
    B.CmdCreateBlock(bid("entry")),
    B.CmdSwitchToBlock(bid("entry")),
    B.CmdBindEntryParams(bid("entry"), { vid("x") }),
    B.CmdReturnValue(vid("x")),
    B.CmdSealBlock(bid("entry")),
    B.CmdFinishFunc(fid("f")),
    B.CmdFinalizeModule,
})

local m = Collect.run(program)
assert(pvm.classof(m) == D.DPhaseModule)
local mm = Mx.phase_module_maps(m)
assert(mm.sigs["sig:f"] ~= nil)
assert(mm.funcs["f"] ~= nil)
assert(mm.funcs["f"].body ~= nil and #mm.funcs["f"].body > 0)

print("dasm phase collect: ok")
