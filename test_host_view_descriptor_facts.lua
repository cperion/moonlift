package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local BufferView = require("moonlift.buffer_view")
local HostFacts = require("moonlift.host_layout_facts")

local T = pvm.context()
A.Define(T)
local HF = HostFacts.Define(T)
local H = T.Moon2Host
local Ty = T.Moon2Type
local C = T.Moon2Core

local UserBuf = BufferView.define_record({
    name = "HostViewUser",
    ctype = "MoonliftHostViewUser",
    cdef = [[
        typedef struct MoonliftHostViewUser {
            int32_t id;
            int32_t age;
            int32_t active;
        } MoonliftHostViewUser;
    ]],
    fields = {
        { name = "id", kind = "i32" },
        { name = "age", kind = "i32" },
        { name = "active", kind = "i32", storage_kind = "i32", expose_kind = "bool" },
    },
})

local user_layout = HF.type_layout_from_buffer_view(UserBuf)
local descriptor, cdef = HF.view_descriptor_for_layout(user_layout, { name = "Users", module_name = "demo" })
assert(pvm.classof(descriptor) == H.HostViewDescriptor)
assert(descriptor.name == "Users")
assert(pvm.classof(descriptor.abi) == H.HostViewAbiStrided)
assert(descriptor.abi.elem_layout == user_layout)
assert(descriptor.abi.stride_unit == H.HostStrideElements)
assert(pvm.classof(descriptor.descriptor_layout) == H.HostTypeLayout)
assert(descriptor.descriptor_layout.kind == H.HostLayoutViewDescriptor)
assert(#descriptor.descriptor_layout.fields == 3)
assert(descriptor.descriptor_layout.fields[1].name == "data")
assert(pvm.classof(descriptor.descriptor_layout.fields[1].rep) == H.HostRepPtr)
assert(pvm.classof(descriptor.descriptor_layout.fields[1].rep.pointee) == Ty.TNamed)
assert(descriptor.descriptor_layout.fields[2].name == "len")
assert(descriptor.descriptor_layout.fields[2].rep.scalar == C.ScalarIndex)
assert(descriptor.descriptor_layout.fields[3].name == "stride")
assert(descriptor.descriptor_layout.fields[3].rep.scalar == C.ScalarIndex)
assert(cdef.source:match("typedef struct MoonView_HostViewUser"))
assert(cdef.source:match("MoonliftHostViewUser%* data;"))
assert(cdef.source:match("intptr_t len;"))
assert(cdef.source:match("intptr_t stride;"))

local facts, fact_descriptor, fact_layout = HF.fact_set_for_view_descriptor(user_layout, { name = "Users" })
assert(pvm.classof(facts) == H.HostFactSet)
assert(fact_descriptor.name == "Users")
assert(fact_layout == fact_descriptor.descriptor_layout)
assert(pvm.classof(facts.facts[1]) == H.HostFactTypeLayout)
assert(pvm.classof(facts.facts[2]) == H.HostFactCdef)
assert(pvm.classof(facts.facts[#facts.facts]) == H.HostFactViewDescriptor)

local expose = H.HostExposeDecl(
    H.HostExposeView(Ty.TNamed(Ty.TypeRefGlobal("demo", "HostViewUser"))),
    "Users",
    {
        H.HostExposeFacet(H.HostExposeLua, H.HostExposeAbiDefault, H.HostExposeProxy(H.HostProxyView, H.HostProxyCacheNone, H.HostReadonly, H.HostBoundsChecked)),
        H.HostExposeFacet(H.HostExposeTerra, H.HostExposeAbiDescriptor, H.HostExposeProxy(H.HostProxyView, H.HostProxyCacheNone, H.HostReadonly, H.HostBoundsChecked)),
        H.HostExposeFacet(H.HostExposeC, H.HostExposeAbiDescriptor, H.HostExposeProxy(H.HostProxyView, H.HostProxyCacheNone, H.HostReadonly, H.HostBoundsChecked)),
    }
)
assert(pvm.classof(expose) == H.HostExposeDecl)
assert(pvm.classof(H.HostLifetimeBorrowed("input")) == H.HostLifetimeBorrowed)

local access = HF.view_access_plan(descriptor)
assert(pvm.classof(access) == H.HostAccessPlan)
assert(pvm.classof(access.subject) == H.HostAccessView)
assert(access.subject.descriptor == descriptor)
assert(access.entries[1].key == H.HostAccessLen)
assert(pvm.classof(access.entries[1].op) == H.HostAccessViewLen)
assert(access.entries[2].key == H.HostAccessData)
assert(pvm.classof(access.entries[2].op) == H.HostAccessViewData)
assert(access.entries[3].key == H.HostAccessStride)
assert(pvm.classof(access.entries[3].op) == H.HostAccessViewStride)
assert(access.entries[4].key == H.HostAccessIndex)
assert(pvm.classof(access.entries[4].op) == H.HostAccessViewIndex)
assert(pvm.classof(access.entries[5].key) == H.HostAccessMethod)
assert(access.entries[5].key.name == "get_id")
assert(pvm.classof(access.entries[5].op) == H.HostAccessViewFieldAt)
assert(pvm.classof(access.entries[#access.entries].op) == H.HostAccessMaterializeTable)
assert(pvm.classof(access.entries[#access.entries].op.subject) == H.HostAccessView)

local lua_plan = H.HostLuaFfiPlan("demo", { cdef }, { access })
assert(pvm.classof(lua_plan) == H.HostLuaFfiPlan)
assert(lua_plan.cdefs[1] == cdef)
assert(lua_plan.access_plans[1] == access)
local terra_plan = H.HostTerraPlan("demo", "-- terra", { user_layout, descriptor.descriptor_layout }, { descriptor })
assert(pvm.classof(terra_plan) == H.HostTerraPlan)
local c_plan = H.HostCPlan("demo.h", cdef.source, { user_layout, descriptor.descriptor_layout }, { descriptor })
assert(pvm.classof(c_plan) == H.HostCPlan)
assert(pvm.classof(H.HostExportDescriptorPtr(descriptor)) == H.HostExportDescriptorPtr)
assert(pvm.classof(H.HostExportExpandedScalars(Ty.TView(Ty.TNamed(Ty.TypeRefGlobal("demo", "HostViewUser"))))) == H.HostExportExpandedScalars)
assert(pvm.classof(H.HostFactLuaFfi(lua_plan)) == H.HostFactLuaFfi)
assert(pvm.classof(H.HostFactTerra(terra_plan)) == H.HostFactTerra)
assert(pvm.classof(H.HostFactC(c_plan)) == H.HostFactC)

print("moonlift host_view_descriptor_facts ok")
