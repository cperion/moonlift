package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local HostAbi = require("moonlift.host_arena_abi")
local ValueProxy = require("moonlift.value_proxy")

local User = HostAbi.define_record({
    name = "AbiTestUser",
    ctype = "MoonliftAbiTestUser",
    cdef = [[
        typedef struct MoonliftAbiTestUser {
            uint32_t type_id;
            uint32_t tag;
            int32_t id;
            int32_t age;
            uint8_t active;
            uint8_t _pad[3];
            double score;
        } MoonliftAbiTestUser;
    ]],
    fields = {
        { name = "id", kind = "i32" },
        { name = "age", kind = "i32" },
        { name = "active", kind = "bool" },
        { name = "score", kind = "f64" },
    },
})

function User.methods:age_plus_one()
    return self.age + 1
end

function User.methods:is_active_adult()
    return self.active and self.age >= 18
end

local user = User:new({ id = 42, age = 27, active = true, score = 3.5 })
assert(ValueProxy.is_proxy(user))
assert(tostring(user) == "MoonHostRecord(AbiTestUser)")
assert(user.id == 42)
assert(user.age == 27)
assert(user.active == true)
assert(user.score == 3.5)
assert(user:age_plus_one() == 28)
assert(user:is_active_adult() == true)
assert(user:raw_ref()[0].type_id == User.type_id)
assert(user:ptr().id == 42)
assert(user:owner().layout == User)

local seen = {}
for k, v in user:pairs() do seen[k] = v end
assert(seen.id == 42)
assert(seen.age == 27)
assert(seen.active == true)
assert(seen.score == 3.5)

local t = user:to_table()
assert(t.id == 42)
assert(t.age == 27)
assert(t.active == true)
assert(t.score == 3.5)

local ok_mut, mut_err = pcall(function() user.age = 30 end)
assert(not ok_mut and tostring(mut_err):find("immutable", 1, true))

local raw = ffi.new("MoonliftAbiTestUser[1]")
raw[0].id = 7
raw[0].age = 19
raw[0].active = 0
raw[0].score = 9.25
local wrapped = User:wrap(raw)
assert(wrapped.id == 7)
assert(wrapped.age == 19)
assert(wrapped.active == false)
assert(wrapped.score == 9.25)
assert(wrapped:age_plus_one() == 20)
assert(wrapped:ptr().score == 9.25)

print("moonlift host arena abi ok")
