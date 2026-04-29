package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local HostAbi = require("moonlift.host_arena_abi")
local Native = require("moonlift.host_arena_native")

local User = HostAbi.define_record({
    name = "NativeAbiUser",
    ctype = "MoonliftNativeAbiUser",
    cdef = [[
        typedef struct MoonliftNativeAbiUser {
            uint32_t type_id;
            uint32_t tag;
            int32_t id;
            int32_t age;
            uint8_t active;
            uint8_t _pad[3];
            double score;
        } MoonliftNativeAbiUser;
    ]],
    fields = {
        { name = "id", kind = "i32" },
        { name = "age", kind = "i32" },
        { name = "active", kind = "bool" },
        { name = "score", kind = "f64" },
    },
})

function User.methods:summary()
    return self.id + self.age + (self.active and 1 or 0) + math.floor(self.score)
end

local session = Native.session()
local user = session:alloc_record(User, { id = 101, age = 44, active = true, score = 8.75 })
assert(user.id == 101)
assert(user.age == 44)
assert(user.active == true)
assert(user.score == 8.75)
assert(user:summary() == 154)
assert(user:owner() == session)
assert(user:raw_ref()[0].session_id == session:id())
assert(user:raw_ref()[0].reserved == session:generation())
assert(user:raw_ref()[0].value_id == 0)
assert(user:ptr().id == 101)

local ok_const = pcall(function() user:ptr().age = 45 end)
assert(not ok_const, "host arena proxies expose const typed pointers by default")

local host_ref = user:raw_ref()[0]
local host_ptr, err = session:ptr_for_ref(user)
assert(host_ptr, err)
assert(host_ptr.ptr == user:ptr())
assert(host_ptr.session_id == session:id())

session:reset()
local stale_ptr, stale_err = session:ptr_for_ref(host_ref)
assert(stale_ptr == nil)
assert(tostring(stale_err):find("stale", 1, true))

local user2 = session:alloc_record(User, { id = 7, age = 9, active = false, score = 1.25 })
assert(user2.id == 7)
assert(user2:raw_ref()[0].reserved == session:generation())

local users = session:alloc_records(User, {
    { id = 1, age = 10, active = true, score = 1.5 },
    { id = 2, age = 20, active = false, score = 2.5 },
    { id = 3, age = 30, active = true, score = 3.5 },
})
assert(#users == 3)
assert(users[1].id == 1 and users[1].age == 10 and users[1].active == true and users[1].score == 1.5)
assert(users[2].id == 2 and users[2].age == 20 and users[2].active == false and users[2].score == 2.5)
assert(users[3].id == 3 and users[3].age == 30 and users[3].active == true and users[3].score == 3.5)
assert(users[1]:raw_ref()[0].value_id + 1 == users[2]:raw_ref()[0].value_id)

session:free()
print("moonlift host arena native ok")
