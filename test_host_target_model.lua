package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local HostFacts = require("moonlift.host_layout_facts")

local T = pvm.context()
A.Define(T)
local HF = HostFacts.Define(T)
local H = T.Moon2Host

local host = HF.default_target_model()
assert(pvm.classof(host) == H.HostTargetModel)
assert(host.pointer_bits == 32 or host.pointer_bits == 64)
assert(host.index_bits == host.pointer_bits)
assert(host.endian == H.HostEndianLittle or host.endian == H.HostEndianBig)

local target32 = H.HostTargetModel(32, 32, H.HostEndianLittle)
local target64 = H.HostTargetModel(64, 64, H.HostEndianLittle)
local ps32, pa32 = HF.size_align_for_kind("ptr", target32)
local is32, ia32 = HF.size_align_for_kind("index", target32)
local ps64, pa64 = HF.size_align_for_kind("ptr", target64)
local is64, ia64 = HF.size_align_for_kind("index", target64)
assert(ps32 == 4 and pa32 == 4)
assert(is32 == 4 and ia32 == 4)
assert(ps64 == 8 and pa64 == 8)
assert(is64 == 8 and ia64 == 8)

local ptr_field = HF.field_layout({ name = "PtrBox" }, { name = "data", kind = "ptr" }, target32)
assert(ptr_field.size == 4)
assert(ptr_field.align == 4)

local layout_id = H.HostLayoutId("test.Conflicting", "Conflicting")
assert(pvm.classof(H.HostRejectConflictingCdef(layout_id)) == H.HostRejectConflictingCdef)
assert(pvm.classof(H.HostRejectInvalidPackedAlign("Packet", 3)) == H.HostRejectInvalidPackedAlign)
assert(pvm.classof(H.HostRejectBareBoolInBoundaryStruct("User", "active")) == H.HostRejectBareBoolInBoundaryStruct)

print("moonlift host_target_model ok")
