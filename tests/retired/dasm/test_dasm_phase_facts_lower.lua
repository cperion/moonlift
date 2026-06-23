package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.schema_projection")

local Mx = require("back.dasm.model")
local BuildCfg = require("back.dasm.phases.build_cfg")
local Phi = require("back.dasm.phases.phi_lower")
local Select = require("back.dasm.phases.select_mir")
local TypeValues = require("back.dasm.phases.type_values")
local Extract = require("back.dasm.phases.extract_facts")
local LowerFacts = require("back.dasm.phases.lower_facts")

local T = pvm.context()
A2(T)
Mx.set_context(T)

local B = T.MoonBack
local D = T.MoonDasm

local function vid(s) return B.BackValId(s) end
local function bid(s) return B.BackBlockId(s) end

local body = {
    B.CmdCreateBlock(bid("entry")),
    B.CmdCreateBlock(bid("then")),
    B.CmdCreateBlock(bid("else")),
    B.CmdSwitchToBlock(bid("entry")),
    B.CmdBindEntryParams(bid("entry"), { vid("x") }),
    B.CmdConst(vid("k"), B.BackI32, B.BackLitInt("7")),
    B.CmdIntBinary(vid("y"), B.BackIntAdd, B.BackI32, B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), vid("x"), vid("k")),
    B.CmdConst(vid("z0"), B.BackI32, B.BackLitInt("0")),
    B.CmdCompare(vid("c"), B.BackIcmpNe, B.BackShapeScalar(B.BackI32), vid("y"), vid("z0")),
    B.CmdBrIf(vid("c"), bid("then"), {}, bid("else"), {}),
    B.CmdSealBlock(bid("entry")),
    B.CmdSwitchToBlock(bid("then")),
    B.CmdReturnValue(vid("y")),
    B.CmdSealBlock(bid("then")),
    B.CmdSwitchToBlock(bid("else")),
    B.CmdReturnValue(vid("x")),
    B.CmdSealBlock(bid("else")),
}

local cfg = BuildCfg.run(Mx.make_phase_func(body, B.BackFuncId("f")), B.BackSigId("sig:f"))
assert(pvm.classof(cfg) == D.DFuncCFG)

local lowered_cfg = Phi.run(cfg)
local pf = Select.run(lowered_cfg)
assert(pvm.classof(pf) == D.DPhaseFunc)

local sig = { params = { B.BackI32 }, results = { B.BackI32 } }
local typed = TypeValues.run(pf, sig)
assert(pvm.classof(typed) == D.DTypedFunc)
local value_scalars = Mx.scalar_map_from_entries(typed.value_scalars)

local facts = Extract.run(pf, value_scalars)
assert(pvm.classof(facts) == D.DFactSet)
assert(#facts.families > 0)

local saw_intbin = false
local saw_cmp = false
for i = 1, #facts.families do
    local fi = facts.families[i]
    if fi.family.kind == "DFamilyIntBin" then saw_intbin = true end
    if fi.family.kind == "DFamilyCompareBranch" then saw_cmp = true end
end
assert(saw_intbin)
assert(saw_cmp)

local lowered = LowerFacts.run(facts)
assert(pvm.classof(lowered) == D.DLoweredFunc)
assert(#lowered.decisions > 0)

local saw_int_imm = false
local saw_cmp_fused = false
for i = 1, #lowered.decisions do
    local r = lowered.decisions[i].rule
    if r == "intbin.imm32" then saw_int_imm = true end
    if r == "cmp.fused-branch" then saw_cmp_fused = true end
end
assert(saw_int_imm)
assert(saw_cmp_fused)

print("dasm phase extract_facts + lower_facts: ok")
