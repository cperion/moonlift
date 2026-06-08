package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local T = pvm.context(); Schema.Define(T)

local Core = T.MoonCore
local Ty = T.MoonType
local Open = T.MoonOpen
local C = T.MoonC
local api = require("moonlift.type_to_c").Define(T)

local all_scalars = {
    Core.ScalarVoid, Core.ScalarBool,
    Core.ScalarI8, Core.ScalarI16, Core.ScalarI32, Core.ScalarI64,
    Core.ScalarU8, Core.ScalarU16, Core.ScalarU32, Core.ScalarU64,
    Core.ScalarF32, Core.ScalarF64,
    Core.ScalarRawPtr, Core.ScalarIndex,
}
for i = 1, #all_scalars do
    local cty = api.scalar_to_c(all_scalars[i])
    assert(cty ~= nil, "scalar projects: " .. tostring(all_scalars[i]))
end
assert(pvm.classof(api.scalar_to_c(Core.ScalarVoid)) == pvm.classof(C.CBackendVoid))
assert(pvm.classof(api.scalar_to_c(Core.ScalarBool)) == pvm.classof(C.CBackendBool8))
assert(pvm.classof(api.scalar_to_c(Core.ScalarIndex)) == pvm.classof(C.CBackendIndex))
assert(pvm.classof(api.scalar_to_c(Core.ScalarI32)) == C.CBackendScalar)
assert(pvm.classof(api.scalar_to_c(Core.ScalarRawPtr)) == C.CBackendDataPtr)

local i32 = Ty.TScalar(Core.ScalarI32)
local ptr = api.type_to_c(Ty.TPtr(i32), {})
assert(pvm.classof(ptr) == C.CBackendDataPtr)
assert(pvm.classof(ptr.pointee) == C.CBackendScalar)

local arr = api.type_to_c(Ty.TArray(Ty.ArrayLenConst(4), i32), {})
assert(pvm.classof(arr) == C.CBackendArray and arr.count == 4)

local desc_ctx = {}
local slice = api.type_to_c(Ty.TSlice(i32), desc_ctx)
assert(pvm.classof(slice) == C.CBackendNamed, "slice projects to a named descriptor type")
local view = api.type_to_c(Ty.TView(i32), desc_ctx)
assert(pvm.classof(view) == C.CBackendNamed, "view projects to a named descriptor type")
assert(#desc_ctx.types >= 2, "slice/view descriptor declarations are registered")

local ctx = {}
local fn_ty = Ty.TFunc({ i32, i32 }, i32)
local codeptr = api.type_to_c(fn_ty, ctx)
assert(pvm.classof(codeptr) == C.CBackendCodePtr)
assert(#ctx.sig_order == 1)
local again = api.type_to_c(fn_ty, ctx)
assert(again.sig.text == codeptr.sig.text)
assert(#ctx.sig_order == 1, "ensure_sig deduplicates")

local c_sig = C.CFuncSigId("host_sig")
local c_func_ptr = api.type_to_c(Ty.TCFuncPtr(c_sig), {})
assert(pvm.classof(c_func_ptr) == C.CBackendImportedCodePtr and c_func_ptr.sig.text == "host_sig")

local closure = api.type_to_c(Ty.TClosure({ i32 }, i32), {})
assert(pvm.classof(closure) == C.CBackendClosureDescriptor)

local named = api.type_to_c(Ty.TNamed(Ty.TypeRefGlobal("m", "Pair")), {})
assert(pvm.classof(named) == C.CBackendNamed)
assert(named.id.module_name == "m" and named.id.spelling == "Pair")
local local_named = api.type_to_c(Ty.TNamed(Ty.TypeRefLocal(Core.TypeSym("k", "LocalPair"))), {})
assert(pvm.classof(local_named) == C.CBackendNamed and local_named.id.module_name == "local" and local_named.id.spelling == "LocalPair")

local ctype = api.type_to_c(Ty.TCType(C.CTypeId("host", "uint128_t")), {})
assert(pvm.classof(ctype) == C.CBackendNamed and ctype.id.module_name == "host" and ctype.id.spelling == "uint128_t")

local ok_arr, err_arr = pcall(function() api.type_to_c(Ty.TArray(Ty.ArrayLenExpr(T.MoonTree.ExprLit(T.MoonTree.ExprTyped(i32), Core.LitInt("3"))), i32), {}) end)
assert(not ok_arr and tostring(err_arr):match("typechecking must reject ArrayLenExpr"))

local ok_slot, err_slot = pcall(function() api.type_to_c(Ty.TSlot(Open.TypeSlot("T", "T")), {}) end)
assert(not ok_slot and tostring(err_slot):match("open type slot"))

local target = api.default_target({ pointer_bits = 32, endian = "big" })
assert(target.pointer_bits == 32 and target.index_bits == 32)
assert(pvm.classof(target.endian) == pvm.classof(C.CBackendBigEndian))
local target2 = api.default_target({ pointer_bits = 64, index_bits = 32 })
assert(target2.pointer_bits == 64 and target2.index_bits == 32)

io.write("moonlift type_to_c ok\n")
