package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A1 = require("moonlift_legacy.asdl")
local A2 = require("moonlift.asdl")
local OpenFacts = require("moonlift.open_facts")
local OpenValidate = require("moonlift.open_validate")
local OpenExpand = require("moonlift.open_expand")
local Typecheck = require("moonlift.tree_typecheck")
local TreeToBack = require("moonlift.tree_to_back")
local BackValidate = require("moonlift.back_validate")
local Bridge = require("moonlift.back_to_moonlift")
local Jit = require("moonlift_legacy.jit")

local T = pvm.context()
A1.Define(T)
A2.Define(T)

local C, Ty, B, O, Tr = T.Moon2Core, T.Moon2Type, T.Moon2Bind, T.Moon2Open, T.Moon2Tree
local OF = OpenFacts.Define(T)
local OV = OpenValidate.Define(T)
local OE = OpenExpand.Define(T)
local TC = Typecheck.Define(T)
local Lower = TreeToBack.Define(T)
local BV = BackValidate.Define(T)
local bridge = Bridge.Define(T)
local jit_api = Jit.Define(T)

local i32 = Ty.TScalar(C.ScalarI32)
local hit_slot = O.ContSlot("test.hit", "hit", { Tr.BlockParam("pos", i32) })
local region_frag = O.RegionFrag(
    {},
    O.OpenSet({}, {}, {}, { O.SlotCont(hit_slot) }),
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
        { Tr.StmtUseRegionFrag(Tr.StmtSurface, "use.hit", region_frag, {}, fills or {}) }
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

local unfilled = make_module({})
local report = OV.validate(OF.facts_of_module(unfilled))
local saw_cont_issue = false
for i = 1, #report.issues do
    if pvm.classof(report.issues[i]) == O.IssueUnfilledContSlot then
        saw_cont_issue = true
    end
end
assert(saw_cont_issue, "expected unfilled continuation slot issue")

local filled = make_module({ O.SlotBinding(O.SlotCont(hit_slot), O.SlotValueCont(Tr.BlockLabel("found"))) })
local expanded = OE.module(filled)
local checked = TC.check_module(expanded)
assert(#checked.issues == 0, tostring(checked.issues[1]))
local program = Lower.module(checked.module)
local back_report = BV.validate(program)
assert(#back_report.issues == 0, tostring(back_report.issues[1]))
local artifact = jit_api.jit():compile(bridge.lower_program(program))
local ptr = artifact:getpointer(T.MoonliftBack.BackFuncId("cont_slot_smoke"))
local fn = ffi.cast("int32_t (*)(void)", ptr)
assert(fn() == 42)
artifact:free()

print("moonlift continuation slot expand ok")
