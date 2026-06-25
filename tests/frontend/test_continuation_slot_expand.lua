package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local pvm = require("lalin.pvm")
local A2 = require("lalin.schema_projection")
local OpenFacts = require("lalin.open_facts")
local OpenValidate = require("lalin.open_validate")
local OpenExpand = require("lalin.open_expand")

local T = pvm.context()
A2(T)

local C, Ty, B, O, Tr = T.LalinCore, T.LalinType, T.LalinBind, T.LalinOpen, T.LalinTree
local OF = OpenFacts(T)
local OV = OpenValidate(T)
local OE = OpenExpand(T)

local i32 = Ty.TScalar(C.ScalarI32)
local hit_slot = O.ContSlot("test.hit", "hit", { Tr.BlockParam("pos", i32) })
local region_frag = O.RegionFrag(O.NameRefText("hit"),
    {},
    { hit_slot },
    O.OpenSet({}, {}, {}, {}),
    Tr.EntryControlBlock(
        Tr.BlockLabel("emit_hit"),
        {},
        {
            Tr.StmtJumpCont(Tr.StmtSurface, hit_slot, {
                Tr.JumpArg("pos", Tr.ExprLit(Tr.ExprSurface, C.LitInt("42"))),
            }),
        }
    ),
    {}
)

local function make_module(fills)
    local entry = Tr.EntryControlBlock(
        Tr.BlockLabel("start"),
        {},
        { Tr.StmtUseRegionFrag(Tr.StmtSurface, Tr.RegionUseEmit, "use.hit", O.RegionFragRefName("hit"), {}, {}, fills or {}) }
    )
    local found = Tr.ControlBlock(
        Tr.BlockLabel("found"),
        { Tr.BlockParam("pos", i32) },
        { Tr.StmtYieldValue(Tr.StmtSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("pos"))) }
    )
    local body = {
        Tr.StmtReturnValue(
            Tr.StmtSurface,
            Tr.ExprControl(
                Tr.ExprSurface,
                Tr.ControlExprRegion("cont.slot.test", i32, entry, { found })
            )
        ),
    }
    return Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(Tr.FuncExport("cont_slot_smoke", {}, i32, body)) })
end

local unfilled = OE.module(make_module({}), OE.env_with_frags({ region_frag }, {}))
local report = OV.validate(OF.facts_of_module(unfilled))
local saw_cont_issue = false
for i = 1, #report.issues do
    if pvm.classof(report.issues[i]) == O.IssueUnfilledContSlot then
        saw_cont_issue = true
    end
end
assert(saw_cont_issue, "expected unfilled continuation slot issue")

local filled = make_module({ O.ContBinding("hit", O.ContTargetLabel(Tr.BlockLabel("found"))) })
local expanded = OE.module(filled, OE.env_with_frags({ region_frag }, {}))
local compiled = lalin.compile("ContinuationSlotSmoke", expanded)
local fn = compiled.cont_slot_smoke
assert(fn() == 42)

print("lalin continuation slot expand ok")
