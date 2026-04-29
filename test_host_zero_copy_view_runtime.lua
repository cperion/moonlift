package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local A = require("moonlift.asdl")
local pvm = require("moonlift.pvm")
local BufferView = require("moonlift.buffer_view")
local HostFacts = require("moonlift.host_layout_facts")

local T = pvm.context()
A.Define(T)
local HF = HostFacts.Define(T)

local User = BufferView.define_record({
    name = "ZeroCopyUser",
    ctype = "MoonliftZeroCopyUser",
    cdef = [[
        typedef struct MoonliftZeroCopyUser {
            int32_t id;
            int32_t age;
            int32_t active;
        } MoonliftZeroCopyUser;
    ]],
    fields = {
        { name = "id", kind = "i32" },
        { name = "age", kind = "i32" },
        { name = "active", kind = "i32", storage_kind = "i32", expose_kind = "bool" },
    },
})

local user_layout = HF.type_layout_from_buffer_view(User)
local view_descriptor, cdef = HF.view_descriptor_for_layout(user_layout, { name = "ZeroCopyUsers" })
local Users = BufferView.define_view_from_host_descriptor({
    descriptor = view_descriptor,
    elem = User,
    cdef = cdef,
})

local data = ffi.new("MoonliftZeroCopyUser[4]")
data[0].id, data[0].age, data[0].active = 10, 20, 1
data[1].id, data[1].age, data[1].active = 11, 21, 0
data[2].id, data[2].age, data[2].active = 12, 22, 1
data[3].id, data[3].age, data[3].active = 13, 23, 0

local users = Users:new(data, 3, 1, { owner = data })
assert(#users == 3)
assert(users.len == 3)
assert(users.stride == 1)
assert(users:ptr()[0].len == 3)
assert(users:data() == ffi.cast(User:mut_ptr_type(), data))
assert(users[1].id == 10)
assert(users[1].age == 20)
assert(users[1].active == true)
assert(users[2].id == 11)
assert(users[2].active == false)
assert(users:get_id(3) == 12)
assert(users:get_age(3) == 22)
assert(users:get_active(3) == true)

data[0].age = 30
assert(users[1].age == 30)
assert(users:get_age(1) == 30)

local seen = 0
for i, u in users:ipairs() do
    seen = seen + 1
    assert(u.id == 9 + i)
end
assert(seen == 3)

local tabled = users:to_table()
assert(#tabled == 3)
assert(tabled[1].id == 10)
assert(tabled[1].age == 30)
assert(tabled[1].active == true)

local strided = Users:new(data, 2, 2, { owner = data })
assert(#strided == 2)
assert(strided[1].id == 10)
assert(strided[2].id == 12)
assert(strided:get_active(2) == true)

local ok = pcall(function() return users[0] end)
assert(ok == false)
local ok2 = pcall(function() return users:get_id(4) end)
assert(ok2 == false)

local UncheckedUsers = BufferView.define_view_from_host_descriptor({
    name = "ZeroCopyUsersUnchecked",
    descriptor = view_descriptor,
    elem = User,
    cdef = cdef,
    checked = false,
})
local unchecked = UncheckedUsers:new(data, 1, 1, { owner = data })
assert(unchecked:get_id(2) == 11)

print("moonlift host_zero_copy_view_runtime ok")
