package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.schema_projection")
local BuildCfg = require("back.dasm.phases.build_cfg")
local Phi = require("back.dasm.phases.phi_lower")
local Select = require("back.dasm.phases.select_mir")
local Mx = require("back.dasm.model")

local T = pvm.context()
A2(T)
Mx.set_context(T)
local D = T.MoonDasm
local B = T.MoonBack

local body = {
    B.CmdCreateBlock(B.BackBlockId("entry")),
    B.CmdCreateBlock(B.BackBlockId("header")),
    B.CmdAppendBlockParam(B.BackBlockId("header"), B.BackValId("header.i"), B.BackShapeScalar(B.BackI32)),
    B.CmdSwitchToBlock(B.BackBlockId("entry")),
    B.CmdJump(B.BackBlockId("header"), { B.BackValId("zero") }),
}

local cfg = BuildCfg.run(Mx.make_phase_func(body, B.BackFuncId("f")), B.BackSigId("sig:f"))
assert(pvm.classof(cfg) == D.DFuncCFG)

local lowered_cfg = Phi.run(cfg)
assert(pvm.classof(lowered_cfg) == D.DFuncCFG)

local outf = Select.run(lowered_cfg)
assert(pvm.classof(outf) == D.DPhaseFunc)

local out = Mx.phase_func_cmds(outf)
local saw_append = false
local saw_alias = false
for i = 1, #out do
    if out[i].kind == "CmdAppendBlockParam" then saw_append = true end
    if out[i].kind == "CmdAlias" then saw_alias = true end
end

assert(not saw_append)
assert(saw_alias)

print("dasm phase cfg+phi+select: ok")
