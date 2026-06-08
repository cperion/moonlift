package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Tr = T.MoonTree
local Open = T.MoonOpen
local Bn = T.MoonBind
local C = T.MoonC
local TypeToC = require("moonlift.type_to_c").Define(T)
local TreeToC = require("moonlift.tree_to_c").Define(T)
local CPlaces = require("moonlift.c_places").Define(T)
local Helpers = require("moonlift.c_helpers").Define(T)
local Validate = require("moonlift.c_validate").Define(T)

local i32_ty = Ty.TScalar(Core.ScalarI32)
local cctx = { target = TypeToC.default_target({}), layout_env = nil, diagnostics = {}, globals = {}, global_types = {}, global_ids = {}, env = {}, locals = {}, local_types = {}, local_storage = {}, helpers = {}, helpers_by_id = {}, helper_order = {}, sigs = {}, sig_order = {}, types = {}, type_decls_by_id = {} }

local function must_fail(label, fn, pattern)
    local ok, err = pcall(fn)
    assert(not ok, label .. " unexpectedly succeeded")
    err = tostring(err)
    if pattern then assert(err:match(pattern), label .. " error did not match " .. pattern .. ": " .. err) end
end

must_fail("TSlot projection", function()
    TypeToC.type_to_c(Ty.TSlot(Open.TypeSlot("T", "T")), cctx)
end, "slot")

local lit = Tr.ExprLit(Tr.ExprTyped(i32_ty), Core.LitInt("1"))
must_fail("raw ExprDot", function()
    TreeToC.expr_to_c(Tr.ExprDot(Tr.ExprTyped(i32_ty), lit, "field"), cctx)
end, "ExprDot")

must_fail("unresolved ExprCast", function()
    TreeToC.expr_to_c(Tr.ExprCast(Tr.ExprTyped(i32_ty), Core.CastAs, i32_ty, lit), cctx)
end, "ExprCast")

must_fail("ExprClosure without closure conversion", function()
    TreeToC.expr_to_c(Tr.ExprClosure(Tr.ExprTyped(Ty.TClosure({}, i32_ty)), {}, i32_ty, {}), cctx)
end, "ExprClosure")

must_fail("unknown ExprCtor rejected", function()
    TreeToC.expr_to_c(Tr.ExprCtor(Tr.ExprTyped(i32_ty), "E", "V", {}), cctx)
end, "unknown variant constructor")

must_fail("ExprSlotValue rejected", function()
    TreeToC.expr_to_c(Tr.ExprSlotValue(Tr.ExprTyped(i32_ty), Open.ExprSlot("e", "e", i32_ty)), cctx)
end, "ExprSlotValue")

local binding = Bn.Binding(Core.Id("x"), "x", i32_ty, Bn.BindingClassLocalValue)
local ref_place = Tr.PlaceRef(Tr.PlaceTyped(i32_ty), Bn.ValueRefBinding(binding))
must_fail("raw PlaceDot", function()
    CPlaces.place_to_c(Tr.PlaceDot(Tr.PlaceTyped(i32_ty), ref_place, "field"), { env = { x = { id = C.CBackendLocalId("x"), ty = C.CBackendScalar(Core.ScalarI32), binding = binding } } })
end, "PlaceDot")

local i32 = C.CBackendScalar(Core.ScalarI32)
local access = C.CBackendMemoryAccess(i32, 4, C.CBackendMayTrap, true, Core.AtomicSeqCst)
local atomic = C.CBackendHelperUse(Helpers.helper_id(C.CBackendHelperAtomicLoad(access)), C.CBackendHelperAtomicLoad(access))
local report = Validate.validate(C.CBackendUnit("m", TypeToC.default_target({ dialect = "c99" }), {}, {}, {}, {}, { atomic }, {}))
local saw_atomic_feature = false
for i = 1, #report.issues do if pvm.classof(report.issues[i]) == C.CBackendIssueInvalidTargetFeature then saw_atomic_feature = true end end
assert(saw_atomic_feature, "atomics without C11 target support should be diagnosed")

io.write("moonlift c_backend_negative ok\n")
