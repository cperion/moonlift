package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local BufferView = require("moonlift.buffer_view")
local HostFacts = require("moonlift.host_layout_facts")

local T = pvm.context()
A.Define(T)
local HF = HostFacts.Define(T)
local H = T.MoonHost

local Packet = BufferView.define_record({
    name = "HostLayoutPacket",
    ctype = "MoonliftHostLayoutPacket",
    cdef = [[
        typedef struct MoonliftHostLayoutPacket {
            uint16_t kind;
            uint16_t flags;
            int32_t len;
            uint8_t active;
            uint8_t _pad[3];
        } MoonliftHostLayoutPacket;
    ]],
    fields = {
        { name = "kind", kind = "u16" },
        { name = "flags", kind = "u16" },
        { name = "len", kind = "i32" },
        { name = "active", kind = "bool" },
    },
})

local layout = HF.type_layout_from_buffer_view(Packet)
assert(pvm.classof(layout) == H.HostTypeLayout)
assert(layout.name == "HostLayoutPacket")
assert(layout.ctype == "MoonliftHostLayoutPacket")
assert(layout.size > 0)
assert(#layout.fields == 4)
assert(layout.fields[1].name == "kind")
assert(layout.fields[1].offset == 0)
assert(layout.fields[3].name == "len")
assert(pvm.classof(layout.fields[3].rep) == H.HostRepScalar)
assert(layout.fields[4].name == "active")
assert(pvm.classof(layout.fields[4].rep) == H.HostRepBool)
assert(layout.fields[4].rep.encoding == H.HostBoolU8)

local access = HF.access_plan(layout)
assert(pvm.classof(access) == H.HostAccessPlan)
assert(pvm.classof(access.subject) == H.HostAccessRecord)
assert(access.subject.layout == layout)
assert(#access.entries == 7) -- ptr + four fields + pairs + to_table
assert(pvm.classof(access.entries[1].key) == H.HostAccessMethod)
assert(access.entries[1].key.name == "ptr")
assert(pvm.classof(access.entries[2].op) == H.HostAccessDirectField)

local view = HF.view_plan(layout)
assert(pvm.classof(view) == H.HostViewPlan)
assert(view.owner == H.HostOwnerBufferView)
assert(pvm.classof(view.expose) == H.HostExposeProxy)
assert(view.expose.kind == H.HostProxyBufferView)

local facts, fact_layout, fact_view = HF.fact_set_for_buffer_view(Packet)
assert(pvm.classof(facts) == H.HostFactSet)
assert(fact_layout.name == layout.name)
assert(pvm.classof(fact_view) == H.HostViewPlan)
assert(#facts.facts == 10) -- layout + cdef + four fields + expose + access + view + producer
assert(pvm.classof(facts.facts[1]) == H.HostFactTypeLayout)
assert(pvm.classof(facts.facts[2]) == H.HostFactCdef)
assert(pvm.classof(facts.facts[#facts.facts]) == H.HostFactProducer)

local Jsonish = BufferView.define_record({
    name = "HostLayoutProjectedJsonish",
    ctype = "MoonliftHostLayoutProjectedJsonish",
    cdef = [[
        typedef struct MoonliftHostLayoutProjectedJsonish {
            int32_t active;
        } MoonliftHostLayoutProjectedJsonish;
    ]],
    fields = {
        { name = "active", kind = "i32", storage_kind = "i32", expose_kind = "bool" },
    },
})
local jsonish = HF.type_layout_from_buffer_view(Jsonish)
assert(pvm.classof(jsonish.fields[1].rep) == H.HostRepBool)
assert(jsonish.fields[1].rep.encoding == H.HostBoolI32)

print("moonlift host_layout_facts ok")
