package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("lalin.pvm")
local A2 = require("lalin.schema_projection")
local R = require("back.dasm.phases.regalloc_banked")
local Mx = require("back.dasm.model")

local T = pvm.context()
A2(T)
Mx.set_context(T)

local B = T.LalinBack

local body = {
    B.CmdConst(B.BackValId("a"), B.BackI32, B.BackLitInt("1")),
    B.CmdConst(B.BackValId("b"), B.BackI32, B.BackLitInt("2")),
    B.CmdIntBinary(B.BackValId("c"), B.BackIntAdd, B.BackI32, B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), B.BackValId("a"), B.BackValId("b")),
}

local alloc = R.run(Mx.make_phase_func(body, B.BackFuncId("f")), { a = "BackI32", b = "BackI32", c = "BackI32" })
assert(pvm.classof(alloc) == T.LalinDasm.DBankedRegalloc)

local seen = {}
for i = 1, #alloc.allocs do
    local a = alloc.allocs[i]
    if a.loc.kind == "DLocReg" then seen[a.vreg.text] = true end
end
assert(seen.a and seen.b and seen.c)

print("dasm phase regalloc_banked: ok")
