package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local BufferView = require("moonlift.buffer_view")

local Packet = BufferView.define_record({
    name = "BufferViewPacket",
    ctype = "MoonliftBufferViewPacket",
    cdef = [[
        typedef struct MoonliftBufferViewPacket {
            uint16_t kind;
            uint16_t flags;
            int32_t len;
            uint8_t active;
            uint8_t _pad[3];
        } MoonliftBufferViewPacket;
    ]],
    fields = {
        { name = "kind", kind = "u16" },
        { name = "flags", kind = "u16" },
        { name = "len", kind = "i32" },
        { name = "active", kind = "bool" },
    },
    methods = {},
})

function Packet.methods:is_control()
    return self.kind == 7 and self.active
end

local view = Packet:new({ kind = 7, flags = 3, len = 128, active = true })
assert(view.kind == 7)
assert(view.flags == 3)
assert(view.len == 128)
assert(view.active == true)
assert(view:is_control() == true)
assert(view:ptr().kind == 7)
assert(view:ptr().len == 128)

local t = view:to_table()
assert(t.kind == 7 and t.flags == 3 and t.len == 128 and t.active == true)

local seen = {}
for k, v in view:pairs() do seen[k] = v end
assert(seen.kind == 7 and seen.flags == 3 and seen.len == 128 and seen.active == true)

local ok_const = pcall(function() view:ptr().len = 1 end)
assert(not ok_const, "buffer views expose const typed pointers by default")

print("moonlift buffer_view ok")
