package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Tr = T.MoonTree
local Typecheck = require("moonlift.tree_typecheck")(T)
local Coverage = require("moonlift.c_coverage")

local i32 = Ty.TScalar(Core.ScalarI32)
local dyn_len = Ty.ArrayLenExpr(Tr.ExprLit(Tr.ExprTyped(i32), Core.LitInt("3")))
local dyn_array = Ty.TArray(dyn_len, i32)
local func = Tr.FuncLocal("bad_dyn_array", { Ty.Param("xs", dyn_array) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprLit(Tr.ExprSurface, Core.LitInt("0"))),
})
local result = Typecheck.check_module(Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(func) }))
local saw = false
for i = 1, #result.issues do
    local issue = result.issues[i]
    if pvm.classof(issue) == Tr.TypeIssueExpected and issue.site:match("array length") then saw = true end
end
assert(saw, "ArrayLenExpr should be rejected during typechecking")
assert(Coverage.classification("MoonType.ArrayLen", "ArrayLenExpr").status == "language_rejected")

io.write("moonlift array length policy ok\n")
