package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local HostDeclParse = require("moonlift.host_decl_parse")
local HostDeclValidate = require("moonlift.host_decl_validate")
local HostLayoutResolve = require("moonlift.host_layout_resolve")
local HostViewAbiPlan = require("moonlift.host_view_abi_plan")
local HostAccessPlan = require("moonlift.host_access_plan")
local HostLuaFfiEmitPlan = require("moonlift.host_lua_ffi_emit_plan")
local HostTerraEmitPlan = require("moonlift.host_terra_emit_plan")
local HostCEmitPlan = require("moonlift.host_c_emit_plan")
local TreeFieldResolve = require("moonlift.tree_field_resolve")

local T = pvm.context()
A.Define(T)
local H = T.Moon2Host
local Ty = T.Moon2Type
local C = T.Moon2Core
local Tr = T.Moon2Tree
local Sem = T.Moon2Sem

local DeclParse = HostDeclParse.Define(T)
local DeclValidate = HostDeclValidate.Define(T)
local LayoutResolve = HostLayoutResolve.Define(T)
local ViewAbi = HostViewAbiPlan.Define(T)
local Access = HostAccessPlan.Define(T)
local LuaEmit = HostLuaFfiEmitPlan.Define(T)
local TerraEmit = HostTerraEmitPlan.Define(T)
local CEmit = HostCEmitPlan.Define(T)
local FieldResolve = TreeFieldResolve.Define(T)

local function lid(name) return H.HostLayoutId("demo." .. name, name) end
local function fid(owner, name) return H.HostFieldId("demo." .. owner .. "." .. name, name) end
local function scalar(s) return Ty.TScalar(s) end
local user_ty = Ty.TNamed(Ty.TypeRefGlobal("demo", "User"))

local user_decl = H.HostStructDecl(lid("User"), "User", H.HostReprC, {
    H.HostFieldDecl(fid("User", "id"), "id", scalar(C.ScalarI32), H.HostStorageSame, {}),
    H.HostFieldDecl(fid("User", "age"), "age", scalar(C.ScalarI32), H.HostStorageSame, {}),
    H.HostFieldDecl(fid("User", "active"), "active", scalar(C.ScalarBool), H.HostStorageBool(H.HostBoolI32, C.ScalarI32), {}),
})
local expose_users = H.HostExposeDecl(
    H.HostExposeView(user_ty),
    "Users",
    {
        H.HostExposeFacet(H.HostExposeLua, H.HostExposeAbiDefault, H.HostExposeProxy(H.HostProxyView, H.HostProxyCacheNone, H.HostReadonly, H.HostBoundsChecked)),
        H.HostExposeFacet(H.HostExposeTerra, H.HostExposeAbiDescriptor, H.HostExposeProxy(H.HostProxyView, H.HostProxyCacheNone, H.HostReadonly, H.HostBoundsChecked)),
        H.HostExposeFacet(H.HostExposeC, H.HostExposeAbiDescriptor, H.HostExposeProxy(H.HostProxyView, H.HostProxyCacheNone, H.HostReadonly, H.HostBoundsChecked)),
    }
)

local parsed = DeclParse.parse(H.HostDeclSourceDecls({ H.HostDeclStruct(user_decl), H.HostDeclExpose(expose_users) }))
assert(pvm.classof(parsed) == H.HostDeclSet)
assert(#parsed.decls == 2)
local report = DeclValidate.validate(parsed)
assert(#report.issues == 0)

local target = H.HostTargetModel(64, 64, H.HostEndianLittle)
local layout, layout_facts = LayoutResolve.resolve_layout(user_decl, target)
assert(pvm.classof(layout) == H.HostTypeLayout)
assert(layout.name == "User")
assert(layout.ctype == "User")
assert(layout.size == 12)
assert(layout.align == 4)
assert(#layout.fields == 3)
assert(layout.fields[1].offset == 0)
assert(layout.fields[2].offset == 4)
assert(layout.fields[3].offset == 8)
assert(pvm.classof(layout.fields[3].rep) == H.HostRepBool)
assert(layout.fields[3].rep.encoding == H.HostBoolI32)
assert(layout_facts.facts[2].cdef.source:match("typedef struct User"))

local env = H.HostLayoutEnv({ layout })
local descriptor = ViewAbi.plan_subject(H.HostExposeView(user_ty), env)
assert(pvm.classof(descriptor) == H.HostViewDescriptor)
assert(descriptor.name == "UserView")
assert(descriptor.descriptor_layout.kind == H.HostLayoutViewDescriptor)
local expose_facts = ViewAbi.plan_facts(expose_users, env, target)
assert(pvm.classof(expose_facts) == H.HostFactSet)
local exposed_descriptor, expose_fact_count = nil, 0
for i = 1, #expose_facts.facts do
    if pvm.classof(expose_facts.facts[i]) == H.HostFactViewDescriptor then exposed_descriptor = expose_facts.facts[i].descriptor end
    if pvm.classof(expose_facts.facts[i]) == H.HostFactExpose then
        expose_fact_count = expose_fact_count + 1
        assert(expose_facts.facts[i].public_name == "Users")
    end
end
assert(exposed_descriptor and exposed_descriptor.name == "Users")
assert(expose_fact_count == 3)

local record_access = Access.plan(H.HostAccessRecord(layout))
assert(pvm.classof(record_access.subject) == H.HostAccessRecord)
assert(pvm.classof(record_access.entries[2].op) == H.HostAccessDirectField)
assert(pvm.classof(record_access.entries[4].op) == H.HostAccessDecodeBool)
local ptr_access = Access.plan(H.HostAccessPtr(layout))
assert(pvm.classof(ptr_access.subject) == H.HostAccessPtr)
local view_access = Access.plan(H.HostAccessView(exposed_descriptor))
assert(pvm.classof(view_access.subject) == H.HostAccessView)
assert(view_access.entries[1].key == H.HostAccessLen)
assert(view_access.entries[2].key == H.HostAccessData)
assert(view_access.entries[3].key == H.HostAccessStride)
assert(view_access.entries[4].key == H.HostAccessIndex)
assert(view_access.entries[5].key.name == "get_id")

local all_facts = {}
for i = 1, #layout_facts.facts do all_facts[#all_facts + 1] = layout_facts.facts[i] end
for i = 1, #expose_facts.facts do all_facts[#all_facts + 1] = expose_facts.facts[i] end
all_facts[#all_facts + 1] = H.HostFactAccessPlan(record_access)
all_facts[#all_facts + 1] = H.HostFactAccessPlan(view_access)
local fact_set = H.HostFactSet(all_facts)

local lua_plan = LuaEmit.plan(fact_set, "demo")
assert(pvm.classof(lua_plan) == H.HostLuaFfiPlan)
assert(lua_plan.module_name == "demo")
assert(#lua_plan.cdefs >= 2)
assert(#lua_plan.access_plans == 2)
local terra_plan = TerraEmit.plan(fact_set, "demo")
assert(pvm.classof(terra_plan) == H.HostTerraPlan)
assert(terra_plan.source:match("struct User"))
local c_plan = CEmit.plan(fact_set, "demo.h")
assert(pvm.classof(c_plan) == H.HostCPlan)
assert(c_plan.source:match("typedef struct User"))
assert(#c_plan.views >= 1)

local base = Tr.ExprLit(Tr.ExprTyped(user_ty), C.LitNil)
local dot = Tr.ExprDot(Tr.ExprSurface, base, "active")
local field_ref = FieldResolve.resolve(dot, layout)
assert(pvm.classof(field_ref) == Sem.FieldByOffset)
assert(field_ref.field_name == "active")
assert(field_ref.offset == 8)
assert(pvm.classof(field_ref.ty) == Ty.TScalar)
assert(field_ref.ty.scalar == C.ScalarBool)
assert(pvm.classof(field_ref.storage) == H.HostRepBool)
assert(field_ref.storage.encoding == H.HostBoolI32)

print("moonlift host_pvm_phases ok")
