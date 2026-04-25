package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)

local Q = require("moonlift.meta").Define(T)
local Source = require("moonlift.meta_source").Define(T)
local Query = require("moonlift.meta_query").Define(T)
local Validate = require("moonlift.meta_validate").Define(T)
local Rewrite = require("moonlift.rewrite_meta").Define(T)
local Expand = require("moonlift.expand_meta").Define(T)
local Seal = require("moonlift.seal_meta_to_elab").Define(T)

local i32 = Q.type.i32
local x = Q.param("x", i32)
local rhs = Q.slot.expr("rhs.key", i32, "rhs")

local frag = Source.expr_quote("x + $rhs", {
    params = { x },
    slots = { rhs },
    holes = { rhs = rhs },
    result = i32,
    module_name = "Demo",
})
assert(frag.body.kind == "MetaExprAdd")
assert(frag.body.rhs.slot == rhs)
assert(#frag.open.slots == 1)

local facts = Query.fact_list(frag)
local saw_slot, saw_param = false, false
for i = 1, #facts do
    if facts[i].kind == "MetaFactSlot" and facts[i].slot.slot == rhs then saw_slot = true end
    if facts[i].kind == "MetaFactParamUse" and facts[i].param == x then saw_param = true end
end
assert(saw_slot)
assert(saw_param)

local report = Validate.report(frag, "Demo")
assert(#report.issues == 1)
assert(report.issues[1].kind == "MetaIssueUnfilledExprSlot")

local two = Q.expr.int("2", i32)
local three = Q.expr.int("3", i32)
local rewritten = Rewrite.expr(frag.body, Q.rewrite.set({ Q.rewrite.expr(frag.body.lhs, two) }))
assert(rewritten.lhs == two)
assert(rewritten.rhs == frag.body.rhs)

local stmt = Q.stmt.expr(frag.body)
local stmts = Rewrite.stmts({ stmt }, Q.rewrite.set({ Q.rewrite.stmt(stmt, { Q.stmt.expr(two), Q.stmt.expr(three) }) }))
assert(#stmts == 2)
assert(stmts[1].expr == two)
assert(stmts[2].expr == three)

local use = frag:use("remaining.use", { Q.expr.int("1", i32) }, { rhs:slot_binding(Q.expr.int("4", i32)) })
local expanded = Expand.expr(use)
local closed_report = Validate.report(expanded, "Demo")
assert(#closed_report.issues == 0)
local generic_import = Q.import.value("capture", "capture", i32)
local import_report = Validate.report(Q.open_set({ value_imports = { generic_import } }), "Demo")
assert(#import_report.issues == 1)
assert(import_report.issues[1].kind == "MetaIssueGenericValueImport")
local sealed = Seal.expr(expanded, Seal.env("Demo"))
assert(sealed.kind == "ElabExprAdd")

local source_func = Source.func_quote([[export func add_rhs(x: i32) -> i32
return x + $rhs
end]], { slots = { rhs }, holes = { rhs = rhs }, module_name = "Demo" })
assert(#source_func.open.slots == 1)
local expanded_func = Expand.func(source_func, Q.expand_env(Q.fill_set({ rhs:slot_binding(Q.expr.int("5", i32)) }), {}, ""))
assert(#expanded_func.open.slots == 0)
assert(#Validate.report(expanded_func, "Demo").issues == 0)

print("moonlift meta remaining smoke ok")
