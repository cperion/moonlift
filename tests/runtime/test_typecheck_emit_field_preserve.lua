package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end
local A = require("lalin.schema_projection")

local T = asdl.context()
A(T)
local C = T.LalinCore
local Ty = T.LalinType
local B = T.LalinBind
local Tr = T.LalinTree
local Sem = T.LalinSem
local TC = require("lalin.tree_typecheck")(T)

local function scalar(s) return Ty.TScalar(s) end

local instr_ty = Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name("Instr") })))
local ptr_instr = Ty.TPtr(instr_ty)
local u16 = scalar(C.ScalarU16)
local binding = B.Binding(C.Id("inst"), "inst", ptr_instr, B.BindingClassLocalValue)
local env = B.Env("", { B.ValueEntry("inst", binding) }, {}, {})
local scope = Tr.TypeValueScope(env.module_name, env.values, env.types, env.layouts, Tr.TypeModuleFacts({}, {}, {}))
local expr_input = Tr.TypeExprInput(scope)
local place_input = Tr.TypePlaceInput(scope)

-- This shape occurs after a typed fragment body is copied into a caller and
-- re-typechecked in an environment that does not carry the fragment's layout
-- table. The field access is already typed; rechecking must not degrade it to
-- the base struct/pointer type when field_layout_for cannot resolve by layout.
local base_expr = Tr.ExprRef(Tr.ExprTyped(ptr_instr), B.ValueRefBinding(binding))
local typed_dot = Tr.ExprDot(Tr.ExprTyped(u16), base_expr, "op")
local expr_result = typed_dot:typecheck_tree_expr(expr_input)
assert(expr_result.ty == u16, "typed ExprDot fallback must preserve field type")
assert(expr_result.expr.h.ty == u16)
assert(expr_result.expr.name == "op")

local base_place = Tr.PlaceRef(Tr.PlaceTyped(ptr_instr), B.ValueRefBinding(binding))
local typed_place_dot = Tr.PlaceDot(Tr.PlaceTyped(u16), base_place, "op")
local place_result = typed_place_dot:typecheck_tree_place(place_input)
assert(place_result.ty == u16, "typed PlaceDot fallback must preserve field type")
assert(place_result.place.h.ty == u16)
assert(place_result.place.name == "op")

-- Typechecking an otherwise standalone caller may receive layouts from the
-- host/bundle layout environment rather than from ItemType declarations in the
-- function's module. That layout environment must participate in dot lowering
-- before type expectations are checked.
local inst_param = Ty.Param("inst", ptr_instr)
local source_dot = Tr.ExprDot(Tr.ExprSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("inst")), "op")
local cast_dot = Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, scalar(C.ScalarI32), source_dot)
local func = Tr.FuncExport("read_op", { inst_param }, scalar(C.ScalarI32), {
    Tr.StmtReturnValue(Tr.StmtSurface, cast_dot),
})
local module = Tr.Module(Tr.ModuleTyped("emit_field_test"), { Tr.ItemFunc(func) })
local layout_env = Sem.LayoutEnv({ Sem.LayoutNamed("", "Instr", { Sem.FieldLayout("op", 0, u16) }, 2, 2) })
local module_result = TC.check_module(module, { layout_env = layout_env })
assert(#module_result.issues == 0, "external layout_env should resolve source ExprDot during typecheck")

print("lalin typecheck emit field preserve ok")
