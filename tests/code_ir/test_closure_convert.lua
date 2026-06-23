package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A2 = require("moonlift.schema_projection")
local ClosureConvert = require("moonlift.closure_convert")

local T = pvm.context()
A2(T)
local C, Ty, B, Tr = T.MoonCore, T.MoonType, T.MoonBind, T.MoonTree
local i32 = Ty.TScalar(C.ScalarI32)

local function name_ref(name)
    return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
end

local closure = Tr.ExprClosure(Tr.ExprSurface, { Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, name_ref("x"), Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))))
})

local y_binding = B.Binding(C.Id("local:y"), "y", i32, B.BindingClassLocalValue)
local capture_closure = Tr.ExprClosure(Tr.ExprSurface, { Ty.Param("x", i32) }, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, name_ref("x"), name_ref("y")))
})

-- Since CallTarget was removed from the schema, closure call detection
-- is now handled during typechecking rather than via explicit CallTarget markers.
-- This test verifies that closure conversion correctly hoists closures
-- into helper functions when they appear as callee expressions.
local main = Tr.FuncExport("closure_direct", {}, i32, {
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprCall(Tr.ExprSurface, closure, { Tr.ExprLit(Tr.ExprSurface, C.LitInt("41")) }))
})

local capture_main = Tr.FuncExport("closure_capture", {}, i32, {
    Tr.StmtLet(Tr.StmtSurface, y_binding, Tr.ExprLit(Tr.ExprSurface, C.LitInt("1"))),
    Tr.StmtReturnValue(Tr.StmtSurface,
        Tr.ExprCall(Tr.ExprSurface, capture_closure, { Tr.ExprLit(Tr.ExprSurface, C.LitInt("41")) }))
})

local module = Tr.Module(Tr.ModuleSurface, { Tr.ItemFunc(main), Tr.ItemFunc(capture_main) })
local converted = ClosureConvert(T).module(module)
assert(#converted.items == 4, "closure conversion should hoist two helpers")

-- Verify hoisted helpers are properly named
local has_direct = false
local has_capture = false
for i = 1, #converted.items do
    local item = converted.items[i]
    local cls = pvm.classof(item)
    if cls == Tr.ItemFunc then
        local func_cls = pvm.classof(item.func)
        if func_cls == Tr.FuncLocal then
            if item.func.name:find("closure_direct") then has_direct = true end
            if item.func.name:find("closure_capture") then has_capture = true end
        end
    end
end
assert(has_direct, "should hoist a helper for direct closure")
assert(has_capture, "should hoist a helper for capture closure")

-- Verify main function has descriptor references instead of closure expressions
for i = 1, #converted.items do
    local item = converted.items[i]
    local cls = pvm.classof(item)
    if cls == Tr.ItemFunc then
        local func_cls = pvm.classof(item.func)
        if func_cls == Tr.FuncExport and item.func.name == "closure_direct" then
            local body = item.func.body
            assert(#body > 0, "closure_direct should have body")
            local last = body[#body]
            local last_cls = pvm.classof(last)
            assert(last_cls == Tr.StmtReturnValue, "last stmt should be return")
            local ret_expr = last.value
            local expr_cls = pvm.classof(ret_expr)
            assert(expr_cls == Tr.ExprCall, "should have ExprCall")
            -- The callee should be a descriptor (ExprAgg), not the original closure
            assert(pvm.classof(ret_expr.callee) == Tr.ExprAgg, "callee should be converted to descriptor")
        end
    end
end

print("moonlift closure conversion ok")
